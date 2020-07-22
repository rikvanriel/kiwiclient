#!/usr/bin/env python
#
# Emulates a subset of the hamlib rigctld interface, allowing programs
# like fldigi and wsjtx to query and change the frequency and mode of
# a kiwisdr channel.
#
# The subset of commands corresponds to the commands actually used by
# fldigi and wsjtx.
#
# (C) 2020 Rik van Riel <riel@surriel.com>
# Released under the GNU General Public License (GPL) version 2 or newer

import array
import logging
import socket
import struct
import time
import select

class Rigctld(object):
    def __init__(self, kiwisdrstream=None, port=None, ipaddr=None):
        self._kiwisdrstream = kiwisdrstream
        self._listenport = port
        self._clientsockets = []
        # default localhost on port 6400
        if port == None:
            port = 6400
        if ipaddr == None:
            ipaddr = "127.0.0.1"

        try:
            socket.inet_aton(ipaddr)
            addr = (ipaddr, port)
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        except socket.error:
            addr = (ipaddr, port, 0, 0)
            s = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)

        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.setblocking(0)

        try:
            s.bind(addr)
        except socket.error:
            logging.error("could not bind to port ", port)
            s.close()
            raise

        s.listen()
        self._serversocket = s

    def _set_modulation(self, command):
        # The M (set modulation) command has two parameters:
        # M <mode> <passband>
        # mode is mandatory, passband is optional
        try:
            splitcmd = command.split()
            mod = splitcmd[1]
            try:
                hc = splitcmd[2]
            except:
                hc = None
            # lc = self._kiwisdrstream._lowcut
            freq = self._kiwisdrstream.get_frequency()
            # print("calling set_mod", mod, lc, hc, freq)
            self._kiwisdrstream.set_mod(mod, lc, hc, freq)
            return "RPRT 0\n"
        except:
            return "RPRT -1\n"
            
    def _set_frequency(self, command):
        try:
            # hamlib freq is in Hz, kiwisdr in kHz
            newfreq = command[2:]
            freq = float(newfreq) / 1000
            mod = self._kiwisdrstream.get_mod()
            lc = self._kiwisdrstream.get_lowcut()
            hc = self._kiwisdrstream.get_highcut()
            # print("calling set_mod ", mod, lc, hc, freq)
            self._kiwisdrstream.set_mod(mod, lc, hc, freq)
            return "RPRT 0\n"
        except:
            return "RPRT -1\n"

    def _dump_state(self):
        # hamlib expects this large table of rig info when connecting
        rigctlver = "0\n"
        rig_model = "2\n"
        itu_region = "0\n"
        freqs = "0.000000 30000000.000000"
        modes = "0x2f"  # AM LSB USB CW (NB)FM see hamlib/rig.h
        # no tx power, one VFO per channel, one antenna
        rx_range = "{} {} -1 -1 0x1 0x1\n".format(freqs, modes)
        rx_end = "0 0 0 0 0 0 0\n"
        tx_range = ""
        tx_end = "0 0 0 0 0 0 0\n"
        tuningsteps = ""
        for step in ["1", "100", "1000", "5000", "9000", "10000"]:
            tuningsteps += "{} {}\n".format(modes, step)
        steps_end = "0 0\n"
        ssbfilt = "0xc 2200\n"
        cwfilt = "0x2 500\n"
        amfilt = "0x1 6000\n"
        fmfilt = "0x20 12000\n"
        filt_end = "0 0\n"
        max_rit = "0\n"
        max_xit = "0\n"
        max_ifshift = "0\n"
        announces = "0\n"
        preamp = "\n"
        attenuator = "\n"
        get_func = "0x0\n"
        set_func = "0x0\n"
        get_level = "0x0\n"
        set_level = "0x0\n"
        get_parm = "0x0\n"
        set_parm = "0x0\n"
        vfo_ops = "vfo_ops=0x0\n"
        ptt_type = "ptt_type=0x0\n"
        done = "done\n"

        message = rigctlver + rig_model + itu_region
        message += rx_range + rx_end + tx_range + tx_end
        message += tuningsteps + steps_end
        message += ssbfilt + cwfilt + amfilt + fmfilt + filt_end
        message += max_rit + max_xit + max_ifshift + announces
        message += preamp + attenuator
        message += get_func + set_func + get_level + set_level
        message += get_parm + set_parm + vfo_ops + ptt_type + done

        return message

    def _handle_command(self, sock, command):
        if command.startswith('q'):
            # quit
            try:
                sock.send("RPRT 0\n".encode('ASCII'))
                sock.close()
                self._clientsockets.remove(sock)
            except:
                pass
            return "RPRT 0\n"
        elif command.startswith('\chk_vfo'):
            return "0\n"
        elif command.startswith('\dump_state'):
            return self._dump_state()
        elif command.startswith('f'):
            # get frequency
            freqinhz = int(self._kiwisdrstream.get_frequency() * 1000)
            return "{}\n".format(freqinhz)
        elif command.startswith('F'):
            return self._set_frequency(command)
        elif command.startswith('m'):
            # get modulation
            highcut = int(self._kiwisdrstream._highcut)
            mod = self._kiwisdrstream._modulation
            return "{}\n{}\n".format(mod, highcut)
        elif command.startswith('M'):
            return self._set_modulation(command)
        elif command.startswith('s'):
            # get split mode
            return "0\nVFOA\n"
        elif command.startswith('v'):
            return "VFOA\n"
            
        print("Received unknown command: ", command)
        return "RPRT 0\n"
 
    def run(self):
        # first accept a new connection, if there is any
        try:
            sock, addr = self._serversocket.accept()
            self._clientsockets.append(sock)
        except socket.error:
            # no new connections this time
            pass

        # check for incoming traffic on existing connections
        read_list = self._clientsockets
        readable, writable, errored = select.select(read_list, [], [], 0)

        for s in errored:
            s.close()
            self._clientsockets.remove(s)

        for s in readable:
            # TODO: add one-char-at-a-time write delay handling
            try:
                command = s.recv(4096)
                try:
                    command = command.decode('ASCII')
                except:
                    # someone sent non-ASCII, just ignore them
                    continue
            except socket.error:
                continue

            if len(command) > 0:
                reply = ""
                # sometimes hamlib programs send multiple commands at once
                for line in command.splitlines():
                    reply += self._handle_command(s, command)
            else:
                continue

            try:
                reply = reply.encode('ASCII')
                s.send(reply)
            except socket.error:
                continue
# EOF
