#
# Example uses of kiwirecorder.py and kiwifax.py
#

# set global environment variables KIWI_HOST and KIWI_PORT to the Kiwi you want to work with
ifeq ($(KIWI_HOST)x,x)
    HOST = kiwisdr.local
else
    HOST = $(KIWI_HOST)
endif

ifeq ($(KIWI_PORT)x,x)
    PORT = 8073
else
    PORT = $(KIWI_PORT)
endif

ifeq ($(KIWI_FREQ)x,x)
    FREQ = 10000
else
    FREQ = $(KIWI_FREQ)
endif

KREC = python kiwirecorder.py

HP = -s $(HOST) -p $(PORT)
H2 = -s $(HOST),$(HOST) -p $(PORT)
H8 = -s $(HOST),$(HOST),$(HOST),$(HOST),$(HOST),$(HOST),$(HOST),$(HOST) -p $(PORT)

F = -f 7550
F_PB = $F -L -5000 -H 5000


# process control help
UNAME = $(shell uname)
ifeq ($(UNAME),Darwin)
# on OS X (Darwin) there is no "interactive mode" for killall command, so use 'kp' BEFORE 'kill' to check
kp:
	killall -d -KILL Python
kill:
#	killall -v -KILL Python
	killall -v Python
else
kp kill:
	killall -r -i -s KILL Python
endif

ps:
	ps ax | grep -i kiwirecorder


# record WSPR audio to file
#
# "-f" frequency is dial frequency, i.e. WSPR center frequency minus passband center (BFO)
# e.g. 40m: cf = 7040.1, so if pb center = 750 then dial = 7040.1 - 0.750 = 7039.35
# NB: most WSPR programs use a pb center of 1500 Hz, not 750 which we use because we think it's easier to listen to

wspr:
	$(KREC) $(HP) --filename=wspr_40m -f 7039.35 --user=WSPR_40m -m iq -L 600 -H 900 --tlimit=110 --log_level=debug

# multiple connections
wspr2:
	$(KREC) $(HP2) --filename=wspr_40m,wspr_30m -f 7039.35,10139.45 --user=WSPR_40m,WSPR_30m -m iq -L 600 -H 900 --tlimit=110


# DRM
# IQ and 10 kHz passband required

DRM_COMMON = -m iq -L -5000 -H 5000 --user=DRM-record --log-level=info
DRM = $(DRM_COMMON) --tlimit=300

drm:
	$(KREC) $(HP) -f $(FREQ) $(DRM)
drm-crash:
	$(KREC) -s nnsdr.proxy.kiwisdr.com -p 8073 -f 13765 $(DRM_COMMON) --filename=AAC.crash.1.13765.12k.iq
drm-crash2:
	$(KREC) -s sysdr.proxy.kiwisdr.com -p 8073 -f 13765 $(DRM_COMMON) --filename=AAC.crash.2.13765.12k.iq
drm-828:
	$(KREC) -s newdelhi.twrmon.net -p 8073 -f 828 $(DRM) --filename=Delhi.828.12k.iq
drm-1368:
	$(KREC) -s newdelhi.twrmon.net -p 8073 -f 1368 $(DRM) --filename=Delhi.1368.12k.iq
drm-621:
	$(KREC) -s bengaluru.twrmon.net -p 8073 -f 621 $(DRM) --filename=Bengaluru.621.12k.iq

# see if Dream works using a real-mode stream (it does)
# requires a Kiwi in 3-channel mode (20.25 kHz) to accomodate a 10 kHz wide USB passband
dream_real:
	$(KREC) $(HP) -f $(FREQ) -m usb -L 0 -H 10000 --ncomp


# FAX
# has both real and IQ mode decoding

fax:
	python kiwifax.py $(HP) -f $(FREQ) -F
faxiq:
	python kiwifax.py $(HP) -f $(FREQ) -F --iq-stream


# Two separate IQ files recording in parallel
HOST_IQ1 = fenu-radio.ddns.net
HOST_IQ2 = southwest.ddns.net

two:
	$(KREC) -s $(HOST_IQ1),$(HOST_IQ2) -p ($PORT) -f 77.5,60 --station=DCF77,MSF -m iq -L -5000 -H 5000


# real mode (non-IQ) file
# Should playback using standard .wav file player

real:
	$(KREC) $(HP) $(F_PB) --tlimit=10
resample:
	$(KREC) $(HP) $(F_PB) -r 6000 --tlimit=10
resample_iq:
	$(KREC) $(HP) $(F_PB) -r 6000 -m iq --tlimit=10
ncomp:
	$(KREC) $(HP) $(F_PB) --ncomp
rx8:
#	$(KREC) $(H8) $(F_PB) --launch-delay=15 --socket-timeout=120 -u krec-RX8
	$(KREC) $(H8) $(F_PB) -u krec-RX8
nb:
	$(KREC) $(HP) $F -m usb --tlimit=10 --nb --nb-gate=200 --nb-th=40
2sec:
	$(KREC) $(HP) $(F_PB) -q --log-level=info --dt-sec=2 
debug:
#	$(KREC) $(HP) $(F_PB) --tlimit=10 --test-mode --log_level=debug
	$(KREC) -s ai,kiwi -p 8073,8074 --filename=wwv1,wwv2 -f 10000 --user=wwv1,wwv2 -m am --tlimit=60 --log-level=info
#	$(KREC) -s ai -p 8073 -f 10000 --user=wwv1 -m am --tlimit=60 --log-level=debug


# S-meter

s_meter:
sm:
	$(KREC) $(HP) $(F_PB) --s-meter=10
	$(KREC) $(HP) $(F_PB) --s-meter=10 -m iq
s_meter_timed:
smt:
	$(KREC) $(HP) $(F_PB) --s-meter=10 --stats
	$(KREC) $(HP) $(F_PB) --s-meter=10 --ncomp --stats
	$(KREC) $(HP) $(F_PB) --s-meter=10 -m iq --stats

s_meter_stream:
sms:
	$(KREC) $(HP) $(F_PB) --s-meter=0 --tlimit=5
s_meter_stream_timed:
smst:
	$(KREC) $(HP) $(F_PB) --s-meter=0 --tlimit=5 --stats
	$(KREC) $(HP) $(F_PB) --s-meter=0 --tlimit=5 --ncomp --stats
	$(KREC) $(HP) $(F_PB) --s-meter=0 --tlimit=5 -m iq --stats

s_meter_stream_timestamps:
smts:
	$(KREC) $(HP) $(F_PB) --s-meter=0 --tlimit=5 --stats --tstamp

s_meter_stream_interval:
smsi:
	$(KREC) $(HP) $(F_PB) --s-meter=0 --tstamp --sdt-sec=1 --stats --log-level=info --dt-sec=4 --snd


# TDoA debugging

tdoa:
	python -u kiwirecorder.py $(HP) $(F_PB) -m iq --kiwi-wav --kiwi-tdoa --tlimit=10 -u krec-TDoA --log-level=warn


# test reported problem situations

T_MODE = -m usb --ncomp     # "no compression" mode used by wsprdaemon.sh
#T_MODE = -m iq
T_PARAMS = -q --log-level=info $(HP) -u test -f 28124.6 $M -L 1200 -H 1700 --test-mode $(T_MODE)

slots1:
	$(KREC) --station=1 $(T_PARAMS) &
slots6:
	$(KREC) --station=1 $(T_PARAMS) &
	$(KREC) --station=2 $(T_PARAMS) &
	$(KREC) --station=3 $(T_PARAMS) &
	$(KREC) --station=4 $(T_PARAMS) &
	$(KREC) --station=5 $(T_PARAMS) &
	$(KREC) --station=6 $(T_PARAMS) &
slots8:
	$(KREC) --station=1 $(T_PARAMS) &
	$(KREC) --station=2 $(T_PARAMS) &
	$(KREC) --station=3 $(T_PARAMS) &
	$(KREC) --station=4 $(T_PARAMS) &
	$(KREC) --station=5 $(T_PARAMS) &
	$(KREC) --station=6 $(T_PARAMS) &
	$(KREC) --station=7 $(T_PARAMS) &
	$(KREC) --station=8 $(T_PARAMS) &
slots14:
	$(KREC) --station=1 $(T_PARAMS) &
	$(KREC) --station=2 $(T_PARAMS) &
	$(KREC) --station=3 $(T_PARAMS) &
	$(KREC) --station=4 $(T_PARAMS) &
	$(KREC) --station=5 $(T_PARAMS) &
	$(KREC) --station=6 $(T_PARAMS) &
	$(KREC) --station=7 $(T_PARAMS) &
	$(KREC) --station=8 $(T_PARAMS) &
	$(KREC) --station=9 $(T_PARAMS) &
	$(KREC) --station=10 $(T_PARAMS) &
	$(KREC) --station=11 $(T_PARAMS) &
	$(KREC) --station=12 $(T_PARAMS) &
	$(KREC) --station=13 $(T_PARAMS) &
	$(KREC) --station=14 $(T_PARAMS) &
slots2:
	$(KREC) --station=1 $(T_PARAMS) &
	$(KREC) --station=2 $(T_PARAMS) &

no_api:
#	$(KREC) $(HP) --no-api
	$(KREC) $(HP) --no-api $(F_PB) --test-mode
no_api_user:
	$(KREC) $(HP) --no-api --user=no_api_test


# IQ file with GPS timestamps

gps:
	$(KREC) $(HP) -f 77.5  -L -5000 -H 5000 -m iq --station=DCF77 --kiwi-wav --log_level info
gps2:
	$(KREC) $(HP) $F -m iq -L -5000 -H 5000 --kiwi-wav


# IQ file without GPS timestamps
# Should playback using standard .wav file player

iq:
	$(KREC) $(HP) $(F_PB) -m iq --tlimit=10 --log_level info


# process waterfall data

wf:
	$(KREC) --wf $(HP) -f $(FREQ) -z 4 --log_level info -u krec-WF --tlimit=2
wf2:
	python kiwiwfrecorder.py $(HP) -f $(FREQ) -z 4 --log_level info -u krec-WF

micro:
	python microkiwi_waterfall.py $(HP) -z 0 -o 0


# stream a Kiwi connection in a "netcat" style fashion

nc:
	python kiwi_nc.py $(HP) $(F_PB) -m am --progress

tun:
	mkfifo /tmp/si /tmp/so
	nc -l localhost 1234 >/tmp/si </tmp/so &
	ssh -f -4 -p 1234 -L 2345:localhost:8073 root@$(HOST) sleep 600 &
	python kiwi_nc.py $(HP) --log debug --admin </tmp/si >/tmp/so


help h:
	@echo HOST = $(HOST)
	@echo PORT = $(PORT)
	@echo FREQ = $(FREQ)
	@echo
	$(KREC) --help

clean:
	-rm -f *.log *.wav *.png *.npy

clean_dist: clean
	-rm -f *.pyc */*.pyc
