#!/usr/bin/env python
## -*- python -*-

import array, logging, os, struct, sys, time, copy, threading, os
import gc
import math
import soundcard as sc
import numpy as np
from copy import copy
from traceback import print_exc
from kiwi import KiwiSDRStream, KiwiWorker
from optparse import OptionParser
from optparse import OptionGroup

HAS_RESAMPLER = True
try:
    ## if available use libsamplerate for resampling
    from samplerate import Resampler
except ImportError:
    ## otherwise linear interpolation is used
    HAS_RESAMPLER = False

class KiwiSoundRecorder(KiwiSDRStream):
    def __init__(self, options):
        super(KiwiSoundRecorder, self).__init__()
        self._options = options
        self._type = 'SND'
        freq = options.frequency
        options.S_meter = False
        #logging.info("%s:%s freq=%d" % (options.server_host, options.server_port, freq))
        self._freq = freq
        self._start_ts = None
        self._start_time = None
        self._squelch = Squelch(self._options) if options.thresh is not None else None
        self._num_channels = 2 if options.modulation == 'iq' else 1
        self._last_gps = dict(zip(['last_gps_solution', 'dummy', 'gpssec', 'gpsnsec'], [0,0,0,0]))
        self._resampler = None
        self._speaker = sc.get_speaker(options.sounddevice)
        self._output_sample_rate = 0
        if self._speaker is None:
            if options.sounddevice is None:
                print('Using default sound device. Specify --sound-device?')
                options.sounddevice = 'default'
            else:
                print("Could not find %s, using default", options.sounddevice)
            self._speaker = sc.default_speaker()


    def _setup_rx_params(self):
        self.set_name(self._options.user)
        mod    = self._options.modulation
        lp_cut = self._options.lp_cut
        hp_cut = self._options.hp_cut
        if mod == 'am':
            # For AM, ignore the low pass filter cutoff
            lp_cut = -hp_cut if hp_cut is not None else hp_cut
        self.set_mod(mod, lp_cut, hp_cut, self._freq)
        if self._options.agc_gain != None:
            self.set_agc(on=False, gain=self._options.agc_gain)
        else:
            self.set_agc(on=True)
        if self._options.compression is False:
            self._set_snd_comp(False)
        if self._options.nb is True:
            gate = self._options.nb_gate
            if gate < 100 or gate > 5000:
                gate = 100
            thresh = self._options.nb_thresh
            if thresh < 0 or thresh > 100:
                thresh = 50
            self.set_noise_blanker(gate, thresh)
        self._output_sample_rate = int(self._sample_rate)
        if self._options.resample > 0:
            self._output_sample_rate = self._options.resample
            self._ratio = float(self._output_sample_rate)/self._sample_rate
            logging.info('resampling from %g to %d Hz (ratio=%f)' % (self._sample_rate, self._options.resample, self._ratio))
            if not HAS_RESAMPLER:
                logging.info("libsamplerate not available: linear interpolation is used for low-quality resampling. "
                             "(pip install samplerate)")
        self._player = self._speaker.player(samplerate=int(self._output_sample_rate), blocksize=4096)
        self._player.__enter__()

    def _process_audio_samples(self, seq, samples, rssi):
        if self._options.quiet is False:
            sys.stdout.write('\rBlock: %08x, RSSI: %6.1f' % (seq, rssi))
            sys.stdout.flush()

        if self._options.resample > 0:
            if HAS_RESAMPLER:
                ## libsamplerate resampling
                if self._resampler is None:
                    self._resampler = Resampler(converter_type='sinc_best')
                samples = np.round(self._resampler.process(samples, ratio=self._ratio)).astype(np.int16)
            else:
                ## resampling by linear interpolation
                n  = len(samples)
                xa = np.arange(round(n*self._ratio))/self._ratio
                xp = np.arange(n)
                samples = np.round(np.interp(xa,xp,samples)).astype(np.int16)


        # Convert the int16 samples [-32768,32,767] to the floating point
        # samples [-1.0,1.0] SoundCard expects
        fsamples = samples.astype(np.float32)
        fsamples /= 32768
        self._player.play(fsamples)

    def _on_sample_rate_change(self):
        if self._options.resample is 0:
            if self._output_sample_rate == int(self._sample_rate):
                return
            # reinitialize player if the playback sample rate changed
            if hasattr(self, 'player'):
                self._player.__exit__(exc_type=None, exc_value=None, traceback=None)
            self._output_sample_rate = int(self._sample_rate)
            self._player = self._speaker.player(samplerate=self._output_sample_rate, blocksize=4096)
            self._player.__enter__()

def options_cross_product(options):
    """build a list of options according to the number of servers specified"""
    def _sel_entry(i, l):
        """if l is a list, return the element with index i, else return l"""
        return l[min(i, len(l)-1)] if type(l) == list else l

    l = []
    multiple_connections = 0
    for i,s in enumerate(options.server_host):
        opt_single = copy(options)
        opt_single.server_host = s
        opt_single.status = 0

        # time() returns seconds, so add pid and host index to make timestamp unique per connection
        opt_single.timestamp = int(time.time() + os.getpid() + i) & 0xffffffff
        for x in ['server_port', 'password', 'tlimit_password', 'frequency', 'agc_gain', 'station', 'user']:
            opt_single.__dict__[x] = _sel_entry(i, opt_single.__dict__[x])
        l.append(opt_single)
        multiple_connections = i
    return multiple_connections,l

def get_comma_separated_args(option, opt, value, parser, fn):
    values = [fn(v.strip()) for v in value.split(',')]
    setattr(parser.values, option.dest, values)
##    setattr(parser.values, option.dest, map(fn, value.split(',')))

def join_threads(snd):
    [r._event.set() for r in snd]
    [t.join() for t in threading.enumerate() if t is not threading.currentThread()]

def main():
    # extend the OptionParser so that we can print multiple paragraphs in
    # the help text
    class MyParser(OptionParser):
        def format_description(self, formatter):
            result = []
            for paragraph in self.description:
                result.append(formatter.format_description(paragraph))
            return "\n".join(result[:-1]) # drop last \n

        def format_epilog(self, formatter):
            result = []
            for paragraph in self.epilog:
                result.append(formatter.format_epilog(paragraph))
            return "".join(result)

    usage = "%prog -s SERVER -p PORT -f FREQ -m MODE [other options]"
    description = ["kiwiclientd.py receives audio from a KiwiSDR and plays"
                   " it to a (virtual) sound device. This can be used to"
                   " send KiwiSDR audio to various programs to decode the"
                   " received signals."
                   " This program also accepts hamlib rigctl commands over"
                   " a network socket to change the kiwisdr frequency",""]
    epilog = [] # text here would go after the options list
    parser = MyParser(usage=usage, description=description, epilog=epilog)
    parser.add_option('-s', '--server-host',
                      dest='server_host', type='string',
                      default='localhost', help='Server host (can be a comma-separated list)',
                      action='callback',
                      callback_args=(str,),
                      callback=get_comma_separated_args)
    parser.add_option('-p', '--server-port',
                      dest='server_port', type='string',
                      default=8073, help='Server port, default 8073 (can be a comma-separated list)',
                      action='callback',
                      callback_args=(int,),
                      callback=get_comma_separated_args)
    parser.add_option('--pw', '--password',
                      dest='password', type='string', default='',
                      help='Kiwi login password (if required, can be a comma-separated list)',
                      action='callback',
                      callback_args=(str,),
                      callback=get_comma_separated_args)
    parser.add_option('--tlimit-pw', '--tlimit-password',
                      dest='tlimit_password', type='string', default='',
                      help='Connect time limit exemption password (if required, can be a comma-separated list)',
                      action='callback',
                      callback_args=(str,),
                      callback=get_comma_separated_args)
    parser.add_option('-u', '--user',
                      dest='user', type='string', default='kiwiclientd',
                      help='Kiwi connection user name (can be a comma-separated list)',
                      action='callback',
                      callback_args=(str,),
                      callback=get_comma_separated_args)
    parser.add_option('--log', '--log-level', '--log_level', type='choice',
                      dest='log_level', default='warn',
                      choices=['debug', 'info', 'warn', 'error', 'critical'],
                      help='Log level: debug|info|warn(default)|error|critical')
    parser.add_option('-q', '--quiet',
                      dest='quiet',
                      default=False,
                      action='store_true',
                      help='Don\'t print progress messages')
    parser.add_option('--tlimit', '--time-limit',
                      dest='tlimit',
                      type='float', default=None,
                      help='Record time limit in seconds. Ignored when --dt-sec used.')
    parser.add_option('--launch-delay', '--launch_delay',
                      dest='launch_delay',
                      type='int', default=0,
                      help='Delay (secs) in launching multiple connections')
    parser.add_option('--connect-retries', '--connect_retries',
                      dest='connect_retries', type='int', default=0,
                      help='Number of retries when connecting to host (retries forever by default)')
    parser.add_option('--connect-timeout', '--connect_timeout',
                      dest='connect_timeout', type='int', default=15,
                      help='Retry timeout(sec) connecting to host')
    parser.add_option('-k', '--socket-timeout', '--socket_timeout',
                      dest='socket_timeout', type='int', default=10,
                      help='Socket timeout(sec) during data transfers')
    parser.add_option('--OV',
                      dest='ADC_OV',
                      default=False,
                      action='store_true',
                      help='Print "ADC OV" message when Kiwi ADC is overloaded')
    parser.add_option('-v', '-V', '--version',
                      dest='krec_version',
                      default=False,
                      action='store_true',
                      help='Print version number and exit')

    group = OptionGroup(parser, "Audio connection options", "")
    group.add_option('-f', '--freq',
                      dest='frequency',
                      type='string', default=1000,
                      help='Frequency to tune to, in kHz (can be a comma-separated list)',
                      action='callback',
                      callback_args=(float,),
                      callback=get_comma_separated_args)
    group.add_option('-m', '--modulation',
                      dest='modulation',
                      type='string', default='am',
                      help='Modulation; one of am, lsb, usb, cw, nbfm, iq (default passband if -L/-H not specified)')
    group.add_option('--ncomp', '--no_compression',
                      dest='compression',
                      default=True,
                      action='store_false',
                      help='Don\'t use audio compression')
    group.add_option('-L', '--lp-cutoff',
                      dest='lp_cut',
                      type='float', default=None,
                      help='Low-pass cutoff frequency, in Hz')
    group.add_option('-H', '--hp-cutoff',
                      dest='hp_cut',
                      type='float', default=None,
                      help='High-pass cutoff frequency, in Hz')
    group.add_option('-r', '--resample',
                      dest='resample',
                      type='int', default=0,
                      help='Resample output file to new sample rate in Hz. The resampling ratio has to be in the range [1/256,256]')
    group.add_option('-T', '--squelch-threshold',
                      dest='thresh',
                      type='float', default=None,
                      help='Squelch threshold, in dB.')
    group.add_option('--squelch-tail',
                      dest='squelch_tail',
                      type='float', default=1,
                      help='Time for which the squelch remains open after the signal is below threshold.')
    group.add_option('-g', '--agc-gain',
                      dest='agc_gain',
                      type='string',
                      default=None,
                      help='AGC gain; if set, AGC is turned off (can be a comma-separated list)',
                      action='callback',
                      callback_args=(float,),
                      callback=get_comma_separated_args)
    group.add_option('--nb',
                      dest='nb',
                      action='store_true', default=False,
                      help='Enable noise blanker with default parameters.')
    group.add_option('--nb-gate',
                      dest='nb_gate',
                      type='int', default=100,
                      help='Noise blanker gate time in usec (100 to 5000, default 100)')
    group.add_option('--nb-th', '--nb-thresh',
                      dest='nb_thresh',
                      type='int', default=50,
                      help='Noise blanker threshold in percent (0 to 100, default 50)')
    parser.add_option_group(group)

    group = OptionGroup(parser, "Sound device options", "")
    group.add_option('--snddev', '--sound-device',
                      dest='sounddevice',
                      type='string', default='',
                      help='Sound device to play kiwi audio on')
    group.add_option('--ls-snd', '--list-sound-devices',
                      dest='list_sound_devices',
                      default=False,
                      action='store_true',
                      help='List available sound devices and exit')
    parser.add_option_group(group)

    group = OptionGroup(parser, "Rig control options", "")
    group.add_option('--rigctl-port', '--rigctl-port',
                      dest='rigctl_port',
                      type='int', default='6400',
                      help='Port listening for rigctl commands (default 6400)')
    group.add_option('--rigctl-addr', '--rigctl-address',
                      dest='rigctl_address',
                      type='string', default='127.0.0.1',
                      help='Address to listen on (default 127.0.0.1)')
    parser.add_option_group(group)

    (options, unused_args) = parser.parse_args()

    ## clean up OptionParser which has cyclic references
    parser.destroy()
    
    if options.krec_version:
        print('kiwiclientd v1.0')
        sys.exit()

    if options.list_sound_devices:
        print(sc.all_speakers())
        sys.exit();

    FORMAT = '%(asctime)-15s pid %(process)5d %(message)s'
    logging.basicConfig(level=logging.getLevelName(options.log_level.upper()), format=FORMAT)
    if options.log_level.upper() == 'DEBUG':
        gc.set_debug(gc.DEBUG_SAVEALL | gc.DEBUG_LEAK | gc.DEBUG_UNCOLLECTABLE)

    run_event = threading.Event()
    run_event.set()

    if options.tlimit is not None and options.dt != 0:
        print('Warning: --tlimit ignored when --dt-sec option used')

    options.sdt = 0
    options.dir = None
    options.raw = False
    options.sound = True
    options.no_api = False
    options.tstamp = False
    options.station = None
    options.filename = None
    options.test_mode = False
    options.is_kiwi_wav = False
    options.is_kiwi_tdoa = False
    gopt = options
    multiple_connections,options = options_cross_product(options)

    snd_recorders = []
    for i,opt in enumerate(options):
        opt.multiple_connections = multiple_connections
        opt.idx = i
        snd_recorders.append(KiwiWorker(args=(KiwiSoundRecorder(opt),opt,run_event)))

    try:
        for i,r in enumerate(snd_recorders):
            if opt.launch_delay != 0 and i != 0 and options[i-1].server_host == options[i].server_host:
                time.sleep(opt.launch_delay)
            r.start()
            #logging.info("started sound recorder %d, timestamp=%d" % (i, options[i].timestamp))
            logging.info("started sound recorder %d" % i)

        while run_event.is_set():
            time.sleep(.1)

    except KeyboardInterrupt:
        run_event.clear()
        join_threads(snd_recorders)
        print("KeyboardInterrupt: threads successfully closed")
    except Exception as e:
        print_exc()
        run_event.clear()
        join_threads(snd_recorders)
        print("Exception: threads successfully closed")

    logging.debug('gc %s' % gc.garbage)

if __name__ == '__main__':
    #import faulthandler
    #faulthandler.enable()
    main()
# EOF
