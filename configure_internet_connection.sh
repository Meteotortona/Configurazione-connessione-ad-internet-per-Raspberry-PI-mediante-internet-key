#!/bin/bash

###########################################################################################
#Copyright (c) <2020> <Meteotortona>
#
#Permission is hereby granted, free of charge, to any person
#obtaining a copy of this software and associated documentation
#files (the "Software"), to deal in the Software without
#restriction, including without limitation the rights to use,
#copy, modify, merge, publish, distribute, sublicense, and/or sell
#copies of the Software, and to permit persons to whom the
#Software is furnished to do so, subject to the following
#conditions:
#
#The above copyright notice and this permission notice shall be
#included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
#EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
#OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
#NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
#HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
#WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
#FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
#OTHER DEALINGS IN THE SOFTWARE.
###########################################################################################

if [[ $EUID -ne 0 ]];
then
	echo ""
	echo "Lo script deve essere eseguito con i privilegi di amministratore."
	echo ""
	echo "Digita il comando 'sudo configure_internet_connection.sh'"
	echo ""
	exit 1
fi

echo ""
echo "Quale operatore telefonico stai utilizzando ?"
echo ""
echo "1 - Tim"
echo "2 - Vodafone"
echo "3 - Iliad"
echo "4 - Ho Mobile"
echo "5 - Wind"
echo "6 - Tre"
echo "7 - Altro operatore"
echo ""
read -p 'Inserisci il numero corrispondente al tuo operatore [1-7]: ' OPERATORE

case "$OPERATORE" in

1)  	APN="ibox.tim.it"
	PHONE="*99#"
    	;;
2)  	APN="web.omnitel.it"
    	PHONE="*99#"
    	;;
3) 	APN="iliad"
    	PHONE="*99#"
    	;;
4) 	APN="web.ho-mobile.it"
    	PHONE="*99#"
   	;;
5)	APN="internet.wind"
    	PHONE="*99***1#"
   	;;
6)  	APN="tre.it"
    	PHONE="*99#"
    	;;
*) 	echo ""
	echo "Operatore non gestito, dovrai procedere ad inserire i parametri manualmente al termine dell'esecuzione dello script"
	echo "Consulta l'area 'problemi comuni' del post per capire come procedere"
	echo ""
	APN="<inserisci APN qui>"
    	PHONE="<inserisci numero da comporre qui>"
   	;;
esac

USERNAME="0"
PASSWORD="0"

#Installazione wvdial
echo ""
echo "Installo wvdial..."
echo ""
apt-get -qq -y install wvdial

#configurazione wvdial
echo ""
echo "Configuro wvdial..."
echo ""
WVDIAL_CONF_FILE="/etc/wvdial.conf"

if ! grep -q "Init1" $WVDIAL_CONF_FILE;
then
	echo "Init1 = ATZ" >> $WVDIAL_CONF_FILE
fi

if ! grep -q "Stupid Mode" $WVDIAL_CONF_FILE;
then
	echo "Stupid Mode = 1" >> $WVDIAL_CONF_FILE
fi

if ! grep -q "Init3" $WVDIAL_CONF_FILE;
then
	echo "Init3 = AT+CGDCONT=1,\"IP\",\"$APN\"" >> $WVDIAL_CONF_FILE
fi

sed -i "s/\; Phone.*/Phone = $PHONE/" $WVDIAL_CONF_FILE
sed -i "s/\; Username.*/Username = $USERNAME/" $WVDIAL_CONF_FILE
sed -i "s/\; Password.*/Password = $PASSWORD/" $WVDIAL_CONF_FILE

#configurazione PPP, viene impostata la chiavetta interntet come "default route"
echo "Configuro PPP..."
echo ""

PPP_CONF_FILE="/etc/ppp/peers/wvdial"

if ! grep -q "replacedefaultroute" $PPP_CONF_FILE;
then
	echo "replacedefaultroute" >> $PPP_CONF_FILE
fi

if ! grep -q "defaultroute" $PPP_CONF_FILE;
then
	echo "defaultroute" >> $PPP_CONF_FILE
fi

#configurazione servizio systemctl per la gestione di wvdial
echo "Configuro il servizio per la connessione..."
echo ""

SERVICE_CONF_FILE="/lib/systemd/system/internetkey.service"

echo "[Unit]" > $SERVICE_CONF_FILE
echo "Description = Service to start up wvdial" >> $SERVICE_CONF_FILE
echo "" >> $SERVICE_CONF_FILE
echo "[Service]" >> $SERVICE_CONF_FILE
echo "ExecStart=/usr/bin/wvdial" >> $SERVICE_CONF_FILE
echo "Restart=always" >> $SERVICE_CONF_FILE
echo "RestartSec=10" >> $SERVICE_CONF_FILE
echo "StartLimitInterval=300" >> $SERVICE_CONF_FILE
echo "StartLimitBurst=30" >> $SERVICE_CONF_FILE
echo "KillMode=process" >> $SERVICE_CONF_FILE
echo "KillSignal=SIGINT" >> $SERVICE_CONF_FILE
echo "SuccessExitStatus=1" >> $SERVICE_CONF_FILE

ln -s /lib/systemd/system/internetkey.service /etc/systemd/system/internetkey.service

systemctl daemon-reload

#identificazione internet key
IFS=$'\n';
readarray ELENCO_DISPOSITIVI < <(lsusb)
NUMERO_DISPOSITIVI=${#ELENCO_DISPOSITIVI[*]}

echo "Quale dei seguenti dispositivi è la Internet Key ?"
echo ""
for (( i=0; i<=$(( $NUMERO_DISPOSITIVI -1 )); i++ ))
do
    echo -ne "$((i + 1)) - ${ELENCO_DISPOSITIVI[$i]}"
done
echo ""
read -p "Inserisci il numero corrispondente al dispositivo [1-$NUMERO_DISPOSITIVI]: " DISPOSITIVO

DISPOSITIVO=$(( $DISPOSITIVO -1 ))

PRODUTTORE=`echo -ne "${ELENCO_DISPOSITIVI[$DISPOSITIVO]}" | grep -o -E 'ID [a-z0-9]{4}\:[a-z0-9]{4}' | cut -d" " -f2 | cut -d":" -f1`
PRODOTTO=`echo -ne "${ELENCO_DISPOSITIVI[$DISPOSITIVO]}" | grep -o -E 'ID [a-z0-9]{4}\:[a-z0-9]{4}' | cut -d" " -f2 | cut -d":" -f2`

#configurazione regola di udev per avviare la connessione nel momento in cui viene inserita la internet key
echo ""
echo "Configuro l'inizializzazione automatica del servizio..."
echo ""

UDEV_CONF_FILE="/etc/udev/rules.d/99-start_internet_connection.rules"

echo "ATTR{idVendor}==\"$PRODUTTORE\", ATTR{idProduct}==\"$PRODOTTO\", TAG+=\"systemd\", ENV{SYSTEMD_WANTS}=\"internetkey.service\"" > $UDEV_CONF_FILE

#installazione fping
echo "Installo fping..."
echo ""
apt-get -qq -y install fping

#deploy script per test e riavvio connessione
echo ""
echo "Deploy script per verifica connessione..."
echo ""

CHECK_CONNECTION_SCRIPT="/home/${SUDO_USER:-$USER}/check_internet_connection.sh"

echo "#!/bin/bash" > $CHECK_CONNECTION_SCRIPT
echo "" >> $CHECK_CONNECTION_SCRIPT
echo "fping -c1 -t 1000 www.google.it > /dev/null 2>&1" >> $CHECK_CONNECTION_SCRIPT
echo "if [ \"$?\" != 0 ]" >> $CHECK_CONNECTION_SCRIPT
echo "then" >> $CHECK_CONNECTION_SCRIPT
echo "	echo `date`\" - Riavvio connessione internet\" >> /home/${SUDO_USER:-$USER}/internet_connection.log" >> $CHECK_CONNECTION_SCRIPT
echo "	systemctl restart internetkey.service" >> $CHECK_CONNECTION_SCRIPT
echo "fi" >> $CHECK_CONNECTION_SCRIPT
echo "" >> $CHECK_CONNECTION_SCRIPT
echo "exit 0" >> $CHECK_CONNECTION_SCRIPT

chmod +x $CHECK_CONNECTION_SCRIPT

#se è stato possibile configurare l'APN viene effettuata la verifica che la connessione vada a buon fine
if [[ $OPERATORE -eq 0  ||  $OPERATORE  -gt 7  ]];
then
	echo ""
	echo "[WARN] Non è stato possibile configurare l'APN corretto per il tuo operatore, visualizza l'area \"problemi comuni\" del post per ulteriori dettagli"
	exit 0
else
	IP_ORIG=`curl -s http://whatismyip.akamai.com/`
	systemctl start internetkey.service
	echo "Test connessione..."
	echo ""
	sleep 15
	IP_NEW=`curl -s http://whatismyip.akamai.com/`
	systemctl stop internetkey.service
	if [[ "$IP_ORIG" != "$IP_NEW" ]];
	then
		echo "[OK] La configurazione della chiavetta è andata a buon fine"
		exit 0
	else
		echo "[FAIL] La configurazione della chiavetta non è andata a buon fine, visualizza l'area \"problemi comuni\" del post per ulteriori dettagli"
		exit 1
	fi
fi

exit 0
