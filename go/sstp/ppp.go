package sstp

import (
	"crypto/md5"
	"crypto/rand"
	"encoding/binary"
	"fmt"
	"net"
	"time"
)

func (s *Session) nextID() byte {
	s.lcpID++
	if s.lcpID == 0 {
		s.lcpID = 1
	}
	return s.lcpID
}

func pppCtl(code, id byte, data []byte) []byte {
	b := make([]byte, 4+len(data))
	b[0], b[1] = code, id
	binary.BigEndian.PutUint16(b[2:], uint16(len(b)))
	copy(b[4:], data)
	return b
}

func opt(typ byte, v []byte) []byte {
	o := make([]byte, 2+len(v))
	o[0], o[1] = typ, byte(len(o))
	copy(o[2:], v)
	return o
}

func parseOpts(p []byte) (map[byte][]byte, error) {
	m := map[byte][]byte{}
	for len(p) >= 2 {
		l := int(p[1])
		if l < 2 || l > len(p) {
			return nil, fmt.Errorf("PPP: плохая опция")
		}
		m[p[0]] = append([]byte{}, p[2:l]...)
		p = p[l:]
	}
	return m, nil
}

// negotiatePPP runs LCP → Auth → IPCP. Incoming data frames (proto IPv4) go into s.in.
// Called with a deadline already set on the TLS conn.
func (s *Session) negotiatePPP(hashBits uint8, nonce []byte) error {
	deadline := time.Now().Add(35 * time.Second)
	ourMRU := uint16(1400)
	lcpOpen, peerOpen := false, false
	authProto := uint16(0) // set by peer ConfReq
	var peerChal, authChal, ntResp []byte
	var peerName string
	authed := false
	ipcpOpen, ipcpPeer := false, false
	var ourIP, peerIP net.IP
	var dns []net.IP

	sendLCP := func(code, id byte, data []byte) error {
		return s.writePPP(protoLCP, pppCtl(code, id, data))
	}
	sendIPCP := func(code, id byte, data []byte) error {
		return s.writePPP(protoIPCP, pppCtl(code, id, data))
	}
	sendCHAP := func(code, id byte, data []byte) error {
		return s.writePPP(protoCHAP, pppCtl(code, id, data))
	}
	sendPAP := func(code, id byte, data []byte) error {
		return s.writePPP(protoPAP, pppCtl(code, id, data))
	}

	// Our LCP ConfReq: MRU + Magic-Number. We do not request auth.
	reqID := s.nextID()
	mb := make([]byte, 4)
	binary.BigEndian.PutUint32(mb, s.magic)
	ourOpts := append(opt(1, []byte{byte(ourMRU >> 8), byte(ourMRU)}), opt(5, mb)...)
	if err := sendLCP(confReq, reqID, ourOpts); err != nil {
		return err
	}
	s.logf("SSTP: LCP ConfReq sent id=%d", reqID)

	for time.Now().Before(deadline) {
		if lcpOpen && peerOpen && authed && ipcpOpen && ipcpPeer {
			s.LocalIP, s.PeerIP, s.DNS = ourIP, peerIP, dns
			s.MTU = int(ourMRU)
			if err := s.cryptoBind(hashBits, nonce, ntResp); err != nil {
				return err
			}
			return nil
		}
		_ = s.conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		ctrl, msg, ppp, attrs, err := s.readFrame()
		if err != nil {
			if ne, ok := err.(interface{ Timeout() bool }); ok && ne.Timeout() {
				if !lcpOpen {
					reqID = s.nextID()
					_ = sendLCP(confReq, reqID, ourOpts)
				}
				continue
			}
			return err
		}
		if ctrl {
			switch msg {
			case msgEchoRequest:
				_ = s.writeControl(msgEchoResponse)
			case msgAbort, msgDisconnect:
				return fmt.Errorf("SSTP: сервер разорвал соединение (msg=%d lcp=%v/%v auth=%v)", msg, lcpOpen, peerOpen, authed)
			case msgConnectAck:
				// late / retransmit — ignore
			default:
			}
			_ = attrs
			continue
		}
		ppp = stripAC(ppp)
		if len(ppp) < 2 {
			continue
		}
		proto := binary.BigEndian.Uint16(ppp[0:])
		body := ppp[2:]
		code := -1
		if len(body) > 0 {
			code = int(body[0])
		}
		s.logf("SSTP: PPP proto=0x%04x len=%d code=%d", proto, len(body), code)
		switch proto {
		case protoLCP:
			if len(body) < 4 {
				continue
			}
			code, id := body[0], body[1]
			data := body[4:]
			switch code {
			case confReq:
				opts, err := parseOpts(data)
				if err != nil {
					continue
				}
				var nak, rej []byte
				for t, v := range opts {
					switch t {
					case 1: // MRU
						if len(v) == 2 {
							m := binary.BigEndian.Uint16(v)
							if m < 576 {
								nak = append(nak, opt(1, []byte{0x05, 0xDC})...) // 1500
							} else if m < ourMRU {
								ourMRU = m
							}
						}
					case 3: // Auth-Protocol
						if len(v) >= 2 {
							authProto = binary.BigEndian.Uint16(v)
							switch authProto {
							case protoCHAP, protoPAP:
								// accept
							default:
								// prefer MS-CHAPv2 (CHAP with algorithm 0x80)
								nak = append(nak, opt(3, []byte{0xc2, 0x23, 0x80})...)
							}
							if authProto == protoCHAP && (len(v) < 3 || v[2] != 0x80 && v[2] != 0x05) {
								// request MS-CHAPv2 specifically when peer offered plain CHAP without algo
								if len(v) < 3 {
									nak = append(nak, opt(3, []byte{0xc2, 0x23, 0x80})...)
								}
							}
						}
					case 5: // Magic-Number — accept any
					case 2, 7, 8: // ACCM / PFC / ACFC — we speak raw PPP, reject
						rej = append(rej, opt(t, v)...)
					default:
						rej = append(rej, opt(t, v)...)
					}
				}
				if len(rej) > 0 {
					_ = sendLCP(confRej, id, rej)
				} else if len(nak) > 0 {
					_ = sendLCP(confNak, id, nak)
				} else {
					_ = sendLCP(confAck, id, data)
					peerOpen = true
					s.logf("SSTP: LCP peer Opened")
				}
			case confAck:
				if id == reqID {
					lcpOpen = true
					s.logf("SSTP: LCP Opened")
				}
			case confNak:
				opts, _ := parseOpts(data)
				if v, ok := opts[1]; ok && len(v) == 2 {
					ourMRU = binary.BigEndian.Uint16(v)
					ourOpts = append(opt(1, v), opt(5, mb)...)
				}
				reqID = s.nextID()
				_ = sendLCP(confReq, reqID, ourOpts)
			case confRej:
				opts, _ := parseOpts(data)
				if _, ok := opts[5]; ok {
					ourOpts = opt(1, []byte{byte(ourMRU >> 8), byte(ourMRU)})
				}
				reqID = s.nextID()
				_ = sendLCP(confReq, reqID, ourOpts)
			case echoReq:
				_ = sendLCP(echoReply, id, append(mb, data[4:]...))
			case termReq:
				_ = sendLCP(termAck, id, nil)
				return fmt.Errorf("SSTP: LCP Terminate")
			}
			if lcpOpen && peerOpen && !authed {
				switch authProto {
				case 0:
					authed = true // no auth required
					s.Auth = "none"
				case protoPAP:
					u, p := []byte(s.cfg.User), []byte(s.cfg.Password)
					d := append([]byte{byte(len(u))}, u...)
					d = append(d, byte(len(p)))
					d = append(d, p...)
					_ = sendPAP(1, s.nextID(), d) // Authenticate-Request
					s.Auth = "PAP"
				case protoCHAP:
					// wait for Challenge
				}
			}
			if lcpOpen && peerOpen && authed && !ipcpOpen {
				s.logf("SSTP: starting IPCP")
				id := s.nextID()
				// request IP address 0.0.0.0 (any) + DNS
				req := opt(3, []byte{0, 0, 0, 0})
				req = append(req, opt(129, []byte{0, 0, 0, 0})...) // primary DNS
				req = append(req, opt(131, []byte{0, 0, 0, 0})...) // secondary DNS
				_ = sendIPCP(confReq, id, req)
				reqID = id // reuse as IPCP req id tracker — careful: share with LCP. Use separate below.
			}
		case protoCHAP:
			if len(body) < 4 {
				continue
			}
			code, id, data := body[0], body[1], body[4:]
			switch code {
			case 1: // Challenge
				if len(data) < 1 {
					continue
				}
				cl := int(data[0])
				if 1+cl > len(data) {
					continue
				}
				authChal = append([]byte{}, data[1:1+cl]...)
				peerName = string(data[1+cl:])
				peerChal = make([]byte, 16)
				rand.Read(peerChal)
				var resp []byte
				algo := byte(0x80) // assume MS-CHAPv2 unless challenge length suggests MD5
				if cl == 16 {
					// could be either; accel-ppp MS-CHAPv2 uses 16-byte challenge
					ntResp = ntResponse(authChal, peerChal, s.cfg.User, s.cfg.Password)
					// MS-CHAPv2 response: 49 bytes = 16 peer_chal + 8 reserved + 24 nt_resp + 1 flags
					resp = make([]byte, 49)
					copy(resp[0:], peerChal)
					copy(resp[24:], ntResp)
				} else {
					// CHAP-MD5
					algo = 0x05
					h := md5.New()
					h.Write([]byte{id})
					h.Write([]byte(s.cfg.Password))
					h.Write(authChal)
					resp = h.Sum(nil)
					_ = algo
				}
				d := append([]byte{byte(len(resp))}, resp...)
				d = append(d, []byte(s.cfg.User)...)
				_ = sendCHAP(2, id, d)
				s.Auth = "MS-CHAPv2"
				s.logf("SSTP: CHAP Response sent (chal=%d)", cl)
				_ = peerName
			case 3: // Success
				authed = true
				s.logf("SSTP: CHAP Success")
				s.logf("SSTP: аутентификация OK (%s)", s.Auth)
				if lcpOpen && peerOpen && !ipcpOpen {
					id := s.nextID()
					req := opt(3, []byte{0, 0, 0, 0})
					req = append(req, opt(129, []byte{0, 0, 0, 0})...)
					req = append(req, opt(131, []byte{0, 0, 0, 0})...)
					_ = sendIPCP(confReq, id, req)
					reqID = id
				}
			case 4: // Failure
				s.logf("SSTP: CHAP Failure %q", string(data))
				return ErrAuth
			}
		case protoPAP:
			if len(body) < 4 {
				continue
			}
			switch body[0] {
			case 2: // Ack
				authed = true
				s.logf("SSTP: аутентификация OK (PAP)")
				if !ipcpOpen {
					id := s.nextID()
					req := opt(3, []byte{0, 0, 0, 0})
					req = append(req, opt(129, []byte{0, 0, 0, 0})...)
					req = append(req, opt(131, []byte{0, 0, 0, 0})...)
					_ = sendIPCP(confReq, id, req)
					reqID = id
				}
			case 3:
				return ErrAuth
			}
		case protoIPCP:
			if len(body) < 4 {
				continue
			}
			code, id, data := body[0], body[1], body[4:]
			switch code {
			case confReq:
				opts, err := parseOpts(data)
				if err != nil {
					continue
				}
				var nak, rej []byte
				ackData := data
				for t, v := range opts {
					switch t {
					case 3: // IP-Address of peer
						if len(v) == 4 {
							peerIP = net.IP(append([]byte{}, v...))
						}
					case 129, 131:
						// peer DNS — ignore on their ConfReq
					default:
						rej = append(rej, opt(t, v)...)
					}
				}
				if len(rej) > 0 {
					_ = sendIPCP(confRej, id, rej)
				} else if len(nak) > 0 {
					_ = sendIPCP(confNak, id, nak)
				} else {
					_ = sendIPCP(confAck, id, ackData)
					ipcpPeer = true
				}
			case confAck:
				opts, _ := parseOpts(data)
				if v, ok := opts[3]; ok && len(v) == 4 {
					ourIP = net.IP(append([]byte{}, v...))
				}
				dns = dns[:0]
				for _, t := range []byte{129, 131} {
					if v, ok := opts[t]; ok && len(v) == 4 && binary.BigEndian.Uint32(v) != 0 {
						dns = append(dns, net.IP(append([]byte{}, v...)))
					}
				}
				ipcpOpen = true
			case confNak:
				opts, _ := parseOpts(data)
				req := []byte{}
				if v, ok := opts[3]; ok && len(v) == 4 {
					req = append(req, opt(3, v)...)
					ourIP = net.IP(append([]byte{}, v...))
				} else {
					req = append(req, opt(3, []byte{0, 0, 0, 0})...)
				}
				for _, t := range []byte{129, 131} {
					if v, ok := opts[t]; ok && len(v) == 4 {
						req = append(req, opt(t, v)...)
					} else {
						req = append(req, opt(t, []byte{0, 0, 0, 0})...)
					}
				}
				id := s.nextID()
				_ = sendIPCP(confReq, id, req)
				reqID = id
			case confRej:
				// drop DNS options, keep IP
				id := s.nextID()
				_ = sendIPCP(confReq, id, opt(3, []byte{0, 0, 0, 0}))
				reqID = id
			case termReq:
				_ = sendIPCP(termAck, id, nil)
				return fmt.Errorf("SSTP: IPCP Terminate")
			}
		case protoIPv4:
			// shouldn't happen before IPCP open, but buffer if it does
			pkt := append([]byte{}, body...)
			select {
			case s.in <- pkt:
			default:
			}
		default:
			// Protocol-Reject for unknown
			_ = sendLCP(protoRej, s.nextID(), ppp[:min(len(ppp), 32)])
		}
	}
	return fmt.Errorf("SSTP: не удалось согласовать PPP за 35 с")
}

func (s *Session) cryptoBind(hashBits uint8, nonce, ntResp []byte) error {
	if len(nonce) == 0 {
		return s.writeControl(msgConnected)
	}
	proto := byte(hashSHA256)
	if hashBits&hashSHA256 == 0 {
		if hashBits&hashSHA1 != 0 {
			proto = hashSHA1
		} else {
			return s.writeControl(msgConnected)
		}
	}
	if len(ntResp) == 0 {
		// no MPPE keys (PAP): send Connected without binding — may fail on strict servers
		return s.writeControl(msgConnected)
	}
	send, _ := mppeKeys(s.cfg.Password, ntResp)
	ch := certHash(s.peer, proto)
	val, _ := compoundMAC(proto, nonce, ch, send)
	return s.writeControl(msgConnected, attr(attrCryptoBinding, val))
}
