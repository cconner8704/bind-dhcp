#!/bin/bash
#set -e
set -x

ROOT_PASSWORD=${ROOT_PASSWORD:-password}
BIND_DATA_DIR=${DATA_DIR}/bind
DHCP_DATA_DIR=${DATA_DIR}/dhcp
WEBMIN_DATA_DIR=${DATA_DIR}/webmin

for SRV_DIR in "bind" "dhcp" "webmin"
do
  mkdir -p ${DATA_DIR}/${SRV_DIR}

  # populate default configuration if it does not exist
  if [ ! -d ${DATA_DIR}/${SRV_DIR}/etc ]; then
    mv /etc/${SRV_DIR} ${DATA_DIR}/${SRV_DIR}/etc
  fi
  rm -rf /etc/${SRV_DIR}
  ln -sf ${DATA_DIR}/${SRV_DIR}/etc /etc/${SRV_DIR}
  echo "Create links for " ${SRV_DIR}
  chmod -R 0775 ${DATA_DIR}/${SRV_DIR}
  
  # bind config
  if [ ${SRV_DIR} = bind ]; then 
    chown -R ${BIND_USER}:${BIND_USER} ${BIND_DATA_DIR}
    if [ ! -d ${BIND_DATA_DIR}/lib ]; then
      mkdir -p ${BIND_DATA_DIR}/lib
      chown ${BIND_USER}:${BIND_USER} ${BIND_DATA_DIR}/lib
    fi
    rm -rf /var/lib/bind
    ln -sf ${BIND_DATA_DIR}/lib /var/lib/bind
	  
    mkdir -m 0775 -p /var/run/named
    mkdir -m 0775 -p /var/cache/bind
    chown root:${BIND_USER} /var/run/named
    chown root:${BIND_USER} /var/cache/bind
  fi

  if [ ${SRV_DIR} = webmin ]; then
    if [ ! "${WEBMIN_ENABLED}" == "true" ]; then
      mv ${DATA_DIR}/${SRV_DIR} ${DATA_DIR}/${SRV_DIR}.moved
    else
      ln -sf ${WEBMIN_DATA_DIR}/etc /etc/webmin
    fi
  fi
  
  # dhcp config
  if [ ${SRV_DIR} = dhcp ]; then
    if [ ! -d ${DHCP_DATA_DIR}/lib ]; then
      mkdir -p ${DHCP_DATA_DIR}/lib
    fi
    rm -rf /var/lib/dhcp
    ln -sf ${DHCP_DATA_DIR}/lib /var/lib/dhcp
    chown -R root:dhcpd ${DHCP_DATA_DIR}/lib
    touch ${DHCP_DATA_DIR}/lib/dhcpd.leases
    touch /var/run/dhcpd.pid
    chown root:dhcpd ${DHCP_DATA_DIR}/lib/dhcpd.leases
    IP="`ifconfig $INTERFACES | awk '/inet addr/{print substr($2,6)}'`"
    MASK="`ifconfig $INTERFACES | grep Mask | cut -d":" -f4`"
    sed -i "s^INTERFACES.*^INTERFACES=\"${INTERFACES}\"^g" /etc/default/isc-dhcp-server
    echo -e '\nlocal7.*\t\t/var/log/dhcp' >> /etc/rsyslog.d/50-default.conf
    DHCP_IP=$(ifconfig -a | grep ${DHCP_SUBNET} | awk '{print $2}')
    sed -i "s^local-address.*^local-address ${DHCP_PI};^g" /etc/dhcp/dhcpd.conf
  fi
done

set_root_passwd() {
  echo "root:$ROOT_PASSWORD" | chpasswd
}

set_root_passwd
echo "Starting webmin..."
/etc/init.d/webmin start

sed -i "/autostart=false/c\autostart=true" /etc/supervisord.conf

NAMED_ORIG="command=NAMED"
NAMED="command=/usr/sbin/named -4 -c /etc/bind/named.conf -f -u bind"
sed -i "s|$NAMED_ORIG|$NAMED|g" /etc/supervisord.conf

#  DHCPD="command=/usr/sbin/dhcpd "$INTERFACES" -pf /var/run/dhcpd.pid -f"
DHCPD_ORIG="command=DHCPD"
#DHCPD="command=/usr/sbin/dhcpd -user dhcpd -group dhcpd -f -4 -pf /var/run/dhcpd.pid -cf /etc/dhcp/dhcpd.conf"
DHCPD="command=/usr/sbin/dhcpd -user dhcpd -group dhcpd -f -4 --no-pid -cf /etc/dhcp/dhcpd.conf"
sed -i "s|$DHCPD_ORIG|$DHCPD|g" /etc/supervisord.conf

exec /usr/bin/supervisord -c /etc/supervisord.conf
