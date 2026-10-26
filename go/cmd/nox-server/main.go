package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"flag"
	"fmt"
	"log"
	"math/big"
	"net"
	"os"
	"os/signal"
	"syscall"
	"time"

	"nox/noxproto"
)

// fileConfig is /etc/nox/server.json. Flags override it.
type fileConfig struct {
	Listen   string `json:"listen"`
	H3       string `json:"h3"`
	Cert     string `json:"cert"`
	Key      string `json:"key"`
	Identity string `json:"identity"`
	PassFile string `json:"passFile"`
	Cover    string `json:"cover"`
	Path     string `json:"path"`
	Profile  string `json:"profile"`
}

func main() {
	genkey := flag.String("genkey", "", "записать новую личность сервера в этот файл и показать ссылку")
	configPath := flag.String("config", "", "JSON-конфиг")
	listen := flag.String("listen", "", "TCP адрес, например 0.0.0.0:443")
	h3 := flag.String("h3", "", "UDP адрес HTTP/3; пусто — выключен; \"off\" — выключить даже если задан в конфиге")
	certFile := flag.String("cert", "", "TLS-сертификат (fullchain.pem)")
	keyFile := flag.String("key", "", "TLS-ключ (privkey.pem)")
	idFile := flag.String("identity", "", "файл личности nox-protocol")
	pass := flag.String("pass", "", "пароль подписки (иначе берётся из личности)")
	passFile := flag.String("pass-file", "", "файл с паролем, одна строка")
	cover := flag.String("cover", "", "URL сайта, который видят клиенты без ключа")
	path := flag.String("path", "", "HTTP-путь туннеля")
	profile := flag.String("profile", "", "browse, video или mixed")
	selfSigned := flag.Bool("self-signed", false, "лабораторный самоподписанный сертификат (не для боя: его видно)")
	sni := flag.String("sni", "nox.local", "имя в самоподписанном сертификате")
	flag.Parse()

	if *genkey != "" {
		if err := writeKey(*genkey, *pass); err != nil {
			log.Fatal(err)
		}
		return
	}

	var fc fileConfig
	if *configPath != "" {
		b, err := os.ReadFile(*configPath)
		if err != nil {
			log.Fatal(err)
		}
		if err := json.Unmarshal(b, &fc); err != nil {
			log.Fatal(err)
		}
	}
	if *listen != "" {
		fc.Listen = *listen
	}
	if *h3 != "" {
		fc.H3 = *h3
	}
	if *certFile != "" {
		fc.Cert = *certFile
	}
	if *keyFile != "" {
		fc.Key = *keyFile
	}
	if *idFile != "" {
		fc.Identity = *idFile
	}
	if *passFile != "" {
		fc.PassFile = *passFile
	}
	if *cover != "" {
		fc.Cover = *cover
	}
	if *path != "" {
		fc.Path = *path
	}
	if *profile != "" {
		fc.Profile = *profile
	}
	if fc.Listen == "" {
		fc.Listen = "0.0.0.0:443"
	}
	if fc.H3 == "off" {
		fc.H3 = ""
	}
	if fc.Identity == "" {
		log.Fatal("нужен -identity или identity в конфиге (создайте: nox-server -genkey /etc/nox/identity)")
	}
	id, err := noxproto.LoadIdentity(fc.Identity)
	if err != nil {
		log.Fatal(err)
	}
	if *pass != "" {
		id.Password = *pass
	} else if fc.PassFile != "" {
		b, err := os.ReadFile(fc.PassFile)
		if err != nil {
			log.Fatal(err)
		}
		id.Password = string(trimNL(b))
	}
	var cert tls.Certificate
	if *selfSigned {
		cert, err = labCert(*sni)
		if err != nil {
			log.Fatal(err)
		}
		log.Print("самоподписанный сертификат: только для проверки на своей машине, в бою его отличают от обычного сайта")
	} else {
		if fc.Cert == "" || fc.Key == "" {
			log.Fatal("нужны -cert и -key (сертификат Let's Encrypt или другого публичного УЦ)")
		}
		cert, err = tls.LoadX509KeyPair(fc.Cert, fc.Key)
		if err != nil {
			log.Fatal(err)
		}
	}
	srv, err := noxproto.Listen(fc.Listen, fc.H3, cert, noxproto.ServerConfig{
		Identity: id,
		Path:     fc.Path,
		Profile:  fc.Profile,
		Cover:    fc.Cover,
	})
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("nox-protocol слушает tcp %s udp %s путь %s", srv.Addr(), emptyDash(srv.UDPAddr()), fc.Path)
	log.Printf("ссылка: %s", sampleLink(id, fc))
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
	_ = srv.Close()
}

func writeKey(path, pass string) error {
	id, err := noxproto.NewIdentity()
	if err != nil {
		return err
	}
	if pass != "" {
		id.Password = pass
	}
	if err := noxproto.SaveIdentity(path, id); err != nil {
		return err
	}
	fmt.Println("identity:", path)
	fmt.Println("public:", noxproto.PubString(id.Public))
	fmt.Println("password:", id.Password)
	fmt.Println("ссылка (подставьте свой домен):")
	fmt.Printf("noxp://%s:%s@YOUR.HOST:443?carrier=h2,h3,cdn&sni=YOUR.HOST&path=/api/v1/events&profile=mixed&fp=chrome#NOX\n",
		noxproto.PubString(id.Public), id.Password)
	return nil
}

func sampleLink(id noxproto.Identity, fc fileConfig) string {
	path := fc.Path
	if path == "" {
		path = "/api/v1/events"
	}
	prof := fc.Profile
	if prof == "" {
		prof = "mixed"
	}
	return fmt.Sprintf("noxp://%s:%s@YOUR.HOST:443?carrier=h2,h3,cdn&sni=YOUR.HOST&path=%s&profile=%s&fp=chrome#NOX",
		noxproto.PubString(id.Public), id.Password, path, prof)
}

func emptyDash(s string) string {
	if s == "" {
		return "—"
	}
	return s
}

func trimNL(b []byte) []byte {
	for len(b) > 0 && (b[len(b)-1] == '\n' || b[len(b)-1] == '\r' || b[len(b)-1] == ' ') {
		b = b[:len(b)-1]
	}
	return b
}

func labCert(name string) (tls.Certificate, error) {
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return tls.Certificate{}, err
	}
	tmpl := &x509.Certificate{
		SerialNumber: big.NewInt(time.Now().UnixNano()),
		Subject:      pkix.Name{CommonName: name},
		NotBefore:    time.Now().Add(-time.Hour),
		NotAfter:     time.Now().Add(365 * 24 * time.Hour),
		DNSNames:     []string{name},
		IPAddresses:  []net.IP{net.ParseIP("127.0.0.1")},
	}
	der, err := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, err
	}
	keyDER, err := x509.MarshalECPrivateKey(key)
	if err != nil {
		return tls.Certificate{}, err
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "EC PRIVATE KEY", Bytes: keyDER})
	return tls.X509KeyPair(certPEM, keyPEM)
}
