#
# Example uses of kiwirecorder.py and kiwifax.py
#

# set global environment variables KIWI_HOST / KIWI_PORT to the location of the Kiwi you want to work with
ifeq ($(KIWI_HOST)x,x)
    HOST = kiwisdr.local
    PORT = 8073
else
    HOST = $(KIWI_HOST)
    PORT = $(KIWI_PORT)
endif

HP = -s $(HOST) -p $(PORT)
H2P = -s $(HOST),$(HOST) -p $(PORT)
H8 = -s $(HOST),$(HOST),$(HOST),$(HOST),$(HOST),$(HOST),$(HOST),$(HOST) -p $(PORT)

F = -f 1440
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
	python kiwirecorder.py $(HP) --filename=wspr_40m -f 7039.35 --user=WSPR_40m -m iq -L 600 -H 900 --tlimit=110 --log_level=debug

# multiple connections
wspr2:
	python kiwirecorder.py $(HP2) --filename=wspr_40m,wspr_30m -f 7039.35,10139.45 --user=WSPR_40m,WSPR_30m -m iq -L 600 -H 900 --tlimit=110


# DRM
# IQ and 10 kHz passband required

FREQ_DRM = 3965

drm:
	python kiwirecorder.py $(HP) -f $(FREQ_DRM) -m iq -L -5000 -H 5000


# FAX
# has both real and IQ mode decoding

# UK
#FREQ_FAX = 2618.5
#FREQ_FAX = 7880

# Australia
FREQ_FAX = 16135

fax:
	python kiwifax.py $(HP) -f $(FREQ_FAX) -F
faxiq:
	python kiwifax.py $(HP) -f $(FREQ_FAX) -F --iq-stream


# Two separate IQ files recording in parallel
HOST_IQ1 = fenu-radio.ddns.net
HOST_IQ2 = southwest.ddns.net

two:
	python kiwirecorder.py -s $(HOST_IQ1),$(HOST_IQ2) -p ($PORT) -f 77.5,60 --station=DCF77,MSF -m iq -L -5000 -H 5000


# real mode (non-IQ) file
# Should playback using standard .wav file player

real:
	python kiwirecorder.py $(HP) $(F_PB) --tlimit=10
resample:
	python kiwirecorder.py $(HP) $(F_PB) -r 6000 --tlimit=10
resample_iq:
	python kiwirecorder.py $(HP) $(F_PB) -r 6000 -m iq --tlimit=10
ncomp:
	python kiwirecorder.py $(HP) $(F_PB) --ncomp
rx8:
#	python kiwirecorder.py $(H8) $(F_PB) --launch-delay=15 --socket-timeout=120 -u krec-RX8
	python kiwirecorder.py $(H8) $(F_PB) -u krec-RX8
nb:
	python kiwirecorder.py $(HP) $F -m usb --tlimit=10 --nb --nb-gate=200 --nb-th=40


# S-meter

s_meter:
sm:
	python kiwirecorder.py $(HP) $(F_PB) --s-meter=10
	python kiwirecorder.py $(HP) $(F_PB) --s-meter=10 -m iq
s_meter_timed:
smt:
	python kiwirecorder.py $(HP) $(F_PB) --s-meter=10 --stats
	python kiwirecorder.py $(HP) $(F_PB) --s-meter=10 --ncomp --stats
	python kiwirecorder.py $(HP) $(F_PB) --s-meter=10 -m iq --stats

s_meter_stream:
sms:
	python kiwirecorder.py $(HP) $(F_PB) --s-meter=0 --tlimit=5
s_meter_stream_timed:
smst:
	python kiwirecorder.py $(HP) $(F_PB) --s-meter=0 --tlimit=5 --stats
	python kiwirecorder.py $(HP) $(F_PB) --s-meter=0 --tlimit=5 --ncomp --stats
	python kiwirecorder.py $(HP) $(F_PB) --s-meter=0 --tlimit=5 -m iq --stats


# TDoA debugging

tdoa:
	python -u kiwirecorder.py $(HP) $(F_PB) -m iq --kiwi-wav --kiwi-tdoa --tlimit=30 -u krec-TDoA


# test reported problem situations

#M = -m usb
M = -m usb --ncomp     # mode used by kiwiwspr.sh
#M = -m iq

slots6:
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=1 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=2 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=3 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=4 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=5 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=6 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
slots8:
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=1 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=2 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=3 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=4 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=5 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=6 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=7 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=8 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
slots14:
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=1 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=2 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=3 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=4 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=5 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=6 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=7 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=8 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=9 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=10 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=11 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=12 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=13 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=14 -f 28124.6 $M -L 1200 -H 1700 --test-mode &
slots2:
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=1 -f 124.6 $M -L 1200 -H 1700 --test-mode &
	python kiwirecorder.py -q --log-level=info $(HP) -u test --station=2 -f 124.6 $M -L 1200 -H 1700 --test-mode &
no_api:
	python kiwirecorder.py $(HP) --no-api
no_api_user:
	python kiwirecorder.py $(HP) --no-api --user=no_api_test


# IQ file with GPS timestamps

gps:
	python kiwirecorder.py $(HP) -f 77.5 --station=DCF77 --kiwi-wav --log_level info -m iq -L -5000 -H 5000
gps2:
	python kiwirecorder.py $(HP) $F --kiwi-wav -m iq -L -5000 -H 5000


# IQ file without GPS timestamps
# Should playback using standard .wav file player

iq:
	python kiwirecorder.py $(HP) $F -m iq --tlimit=10


# process waterfall data

wf:
	python kiwirecorder.py --wf $(HP) -f 10000 -z 4 --log_level info -u krec-WF --tlimit=2

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
	python kiwirecorder.py --help

clean:
	-rm -f *.log *.wav *.png

clean_dist: clean
	-rm -f *.pyc */*.pyc
