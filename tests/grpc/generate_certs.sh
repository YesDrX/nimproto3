#!/bin/bash
# Generate self-signed certificate for localhost testing

echo "Generating self-signed certificate for localhost..."

# Create OpenSSL config file with SANs
cat > openssl.cnf << EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = v3_req

[dn]
C=US
ST=State
L=City
O=Organization
OU=Unit
CN=localhost

[v3_req]
subjectAltName = @alt_names

[alt_names]
DNS.1 = localhost
DNS.2 = *.localhost
IP.1 = 127.0.0.1
IP.2 = ::1
EOF

# Generate private key
openssl genrsa -out server.key 2048

# Generate certificate with SANs
openssl req -new -x509 -key server.key -out server.crt -days 365 \
    -config openssl.cnf -extensions v3_req

# Clean up
rm openssl.cnf

echo ""
echo "Certificate generated successfully!"
echo "Files created:"
echo "  - server.key (private key)"
echo "  - server.crt (certificate)"
echo ""
echo "Verifying certificate SANs:"
openssl x509 -in server.crt -text -noout | grep -A 3 "Subject Alternative Name"
