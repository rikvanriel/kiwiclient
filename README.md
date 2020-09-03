# KiwiClient

This is a Python client for KiwiSDR. It allows you to:

* Receive data streams with audio samples, IQ samples, and waterfall data
* Issue commands to the KiwiSDR

## Dependencies

Make sure the Python package `'numpy'` is installed.
On many Linux distributions the command would be similar to `'apt install python-numpy'`

## Demo code

The following demo programs are provided. Use the `--help` argument to see all program options.

* `kiwirecorder`: Record audio to WAV files, with squelch. Option `--wf` prints various waterfall statistics.
* `kiwiwfrecorder`: Specialty program. Saves waterfall data and GPS timestamps to .npy format file.
* `kiwifax`: Decode radiofax and save as PNGs, with auto start, stop, and phasing.
* `kiwiclientd`: Plays Kiwi audio on sound cards (real & virtual) for use by programs like fldigi and wsjtx.  
    Implements hamlib rigctl network interface so the Kiwi freq & mode can be controlled by these programs.
* `kiwi_nc`: Command line pipeline tool in the style of `netcat` (unfinished).

The `Makefile` contains numerous examples of how to use these programs.

## IS0KYB micro tools

Two utilities have been added to simplify the waterfall data acquisition/storage and data analysis.
The SNR ratio (a la Pierre Ynard) is computed each time.
There is now the possibility to change zoom level and offset frequency (this is still approximate! waiting for jks help ;) )

* `microkiwi_waterfall.py`: launch this program with no filename and just the SNR will be computed, with a filename, the raw waterfall data is saved. Launch with `--help` to list all options.
* `waterfall_data_analysis.ipynb`: this is a demo jupyther notebook to interactively analyze waterfall data. Easily transformable into a standalone python program.

The data is, at the moment, transferred in uncompressed format.

## Guide to the code

### kiwiclient.py

Base class for receiving websocket data from a KiwiSDR.
It provides the following methods which can be used in derived classes:

* `_process_audio_samples(self, seq, samples, rssi)`: audio samples
* `_process_iq_samples(self, seq, samples, rssi, gps)`: IQ samples
* `_process_waterfall_samples(self, seq, samples)`: waterfall data

### kiwirecorder.py
* Can record audio data, IQ samples, and waterfall data (work in progress).
* The complete list of options can be obtained by `python kiwirecorder.py --help`.
* It is possible to record from more than one KiwiSDR simultaneously, see again `--help`.
* For recording IQ samples there is the `-w` or `--kiwi-wav` option: this write	a .wav file which includes GNSS	timestamps (see below).

## IQ .wav files with GNSS timestamps
### kiwirecorder.py configuration
* Use the option `-m iq --kiwi-wav --station=[name]` for recording IQ samples with GNSS time stamps.
* The resulting .wav files contains non-standard WAV chunks with GNSS timestamps.
* If a directory with name `gnss_pos/` exists, a text file `gnss_pos/[name].txt` will be created which contains latitude and longitude as provided by the KiwiSDR; existing files are overwritten.

### Working with the recorded .wav files
* There is an octave extension for reading such WAV files, see `read_kiwi_wav.cc` where the details of the non-standard WAV chunk can be found; it needs to be compiled in this way `mkoctfile read_kiwi_wav.cc`.
* For using read_kiwi_wav an octave function `proc_kiwi_iq_wav.m` is provided; type `help proc_kiwi_iq_wav` in octave for documentation.

