#!/bin/sh
until curl -kX GET "https://localhost:9200/_cat/notes?v&pretty"
do
  sleep 5
done

# This line is really gross but I don't know how else to wrap it. Suggestions
# are welcome!
NEW_PASSWDS=$(docker exec elas01 /bin/bash -c "bin/elasticsearch-setup-passwords auto --batch -Expack.security.http.ssl.key=/usr/share/elasticsearch/config/pki/elas.key.pem -Expack.security.http.ssl.certificate=/usr/share/elasticsearch/config/pki/elas.cert.pem -Expack.security.http.ssl.certificate_authorities=/usr/share/elasticsearch/config/pki/ca.cert.pem --url https://elas01:9200" | grep PASSWORD)

# Extract passwords from utility output
kibana_pass=$(echo "${NEW_PASSWDS}" | grep kibana | awk '{print $NF}')
elastic_pass=$(echo "${NEW_PASSWDS}" | grep elastic | awk '{print $NF}')
beats_pass=$(echo "${NEW_PASSWDS}" | grep beats_system | awk '{print $NF}')

# Write kibana password to default environment file
cat > .env << EOF
KIBANA_PASSWORD=${kibana_pass}
BEATS_PASSWORD=${beats_pass}
EOF

# Restart kibana to apply password change
docker-compose up -d --force-recreate kiba01

# Create admin user
curl -k -XPOST -u elastic:${elastic_pass} 'https://localhost:9200/_security/user/root' -H "Content-Type: application/json" -d '{"password":"changeme","full_name":"root","email":"root@example.com","roles":["superuser"]}'

# Set up example checks
for check in $(find examples -maxdepth 1 -mindepth 1 -type d -printf "%f\n")
do
  # Add check definition
  curl -k -XPOST -u elastic:${elastic_pass} 'https://localhost:9200/checks/_doc' -H 'Content-Type: application/json' -d @examples/${check}/check.json

  # Add admin attributes, if they are defined
  if [ -f examples/${check}/admin-attribs.json ]
  then
    curl -k -XPOST -u elastic:${elastic_pass} https://localhost:9200/attrib_admin_${check}-example/_doc -H "Content-Type: application/json" -d @examples/${check}/admin-attribs.json
  fi

  # Add user attributes, if they are defined
  if [ -f examples/${check}/user-attribs.json ]
  then
    curl -k -XPOST -u elastic:${elastic_pass} https://localhost:9200/attrib_user_${check}-example/_doc -H "Content-Type: application/json" -d @examples/${check}/user-attribs.json
  fi
done