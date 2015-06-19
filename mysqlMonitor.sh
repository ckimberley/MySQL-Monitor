#!/bin/sh
#Testing comment

#This script currently checks for slave status, and possibly for MySQL Enterprise Backup status.  
#Currently it expects that any hostnames ending in 04 are running MySQL Enterprise Backup.  If yes, the monitor looks at the backup tables.

# Test if a terminal is attached. Cron job is not attached to terminal.
TTY=$(tty)
if [ "$TTY" = "not a tty" ]
then
   isTTY="false"
else
   isTTY="true"
fi

#We will connect to the mysql server instance as:
username="user"
password="password"

#Email Variables
sendEmail=false
emailaddress="alias@hostname.com"
hostname="`hostname | sed 's/\.hostname\.com//'`"

#This variable collects all the error/issue info, if there is any.
emailErrorInfo=''

#Populate an array with all the host names.
hosts=("hostname1" "hostname2")

#Begin the loop of our host names.
for i in "${hosts[@]}"
do
   :
   
   #We set this variable to false.  If we find an issue with any of the hosts this variable is flagged to true and an alert will be emailed.
   hostIssue=false

   #Connect to the host and retrieve the contents of 'show slave status'.
   slaveDetails="$(MYSQL_PWD=$password mysql -u$username -h $i -e 'show slave status\G')"

   #Populate error info if Slave_IO_Running is set to No.
   IORun="$(echo "$slaveDetails" | grep Slave_IO_Running:)"
   IORun="$(echo $IORun)"

   if [ "${IORun: -2}" == "No" ]; then

      emailErrorInfo+="\n$i\n"
      emailErrorInfo+="$IORun\n"
      hostIssue=true
   fi

   #Populate error info if Slave_SQL_Running is set to No.
   relayRun="$(echo "$slaveDetails" | grep Slave_SQL_Running:)"
   relayRun="$(echo $relayRun)"

   if [ "${relayRun: -2}" == "No" ]; then

      emailErrorInfo+="\n$i\n"
      emailErrorInfo+="$relayRun\n"
      hostIssue=true
   fi

   #Populate error info if Seconds_Behind_Master is greater than 10 seconds, adjust secondsThreshold to change the second value.
   secondsBehind="$(echo "$slaveDetails" | grep Seconds_Behind_Master:)"
   secondsBehind="$(echo $secondsBehind)"

   secondsThreshold=10
   seconds=${secondsBehind:22}
   seconds="$(echo $seconds)"

   if [[ "$seconds" -gt "$secondsThreshold" ]]; then

      emailErrorInfo+="\n$i\n"
      emailErrorInfo+="$secondsBehind\n"
      hostIssue=true
   fi

   #If an issue was found with replication, we populate the error info with Last_SQL_Error.  NOTE - there may not necessarily be an error, but an alert may still be sent.
   if [ "$hostIssue" = true ]; then

	  sqlState="$(echo "$slaveDetails" | grep Last_SQL_Error:)"
	  sqlState="$(echo $sqlState)"
      
	  emailErrorInfo+="\n$i\n"
      emailErrorInfo+="$sqlState\n"
      sendEmail=true
   fi

   #If a terminal is being run, we print the results thus far, for debugging purposes.
   if [ "$isTTY" = "true" ]
   then
      printf "\n"
      printf "Host: "$i
      printf "\n"
      printf "=========================\n"

      printf "${IORun}"
      printf "\n"

      printf "${relayRun}"
      printf "\n"

      printf "${secondsBehind}"
      printf "\n"

      printf "${sqlState}"
      printf "\n"
   fi

   #Grab the last two characters of the hostname.  If the last two characters are 04 there are backups on the server.  This is a crude way of identifying backup machines and not scalable.
   #A generic means to identify for backups should be found.
   if [  "${i: -2}" -eq "04" ]; then

	  #Connect to the host and retrieve the last record of the mysql.backup_history table.
      lastBackup="$(MYSQL_PWD=$password mysql -u$username -h $i mysql -e 'select * from backup_history order by end_time desc limit 1\G')"

      #backupType="$(echo "$lastBackup" | grep backup_type:)"
      #backupType="$(echo $backupType)"

      #lockTime="$(echo "$lastBackup" | grep lock_time:)"
      #lockTime="$(echo $lockTime)"

      exitState="$(echo "$lastBackup" | grep exit_state:)"
      exitState="$(echo $exitState)"

	  #If the exit state of the last backup does not equal SUCCESS we add the exit state and last error to the error info.
      if [ "${exitState: -7}" != "SUCCESS" ]; then

		 lastError="$(echo "$lastBackup" | grep last_error:)"
		 lastError="$(echo $lastError)"

         emailErrorInfo+="\n$i\n"
         emailErrorInfo+="$exitState\n"
         emailErrorInfo+="$lastError\n"
         sendEmail=true
      fi

	  #Connect to the host and retrieve the last record of the mysql.backup_history table where the backup type was FULL.  Here we are making sure we have taken a backup in the last 25 hours.
      lastFullBackup="$(MYSQL_PWD=$password mysql -u$username -h $i mysql -e 'select * from backup_history where backup_type = "FULL" order by end_time desc limit 1\G')"

	  startTime="$(echo "$lastFullBackup" | grep start_time:)"
      startTime="$(echo $startTime)"

      endTime="$(echo "$lastFullBackup" | grep end_time:)"
      endTime="$(echo $endTime)"

	  #Convert the current time and start time of the backup to a timestamp.
      now=$(date +"%s")
      convertedDate=$(date -d "${startTime: -19}" +"%s")

	  #Subtract the timestamp start time from the current timestamp.
      timeLeft="$((now - convertedDate))"

	  #If timeLeft is greater than 90000 seconds (25 hours) we add this issue to the error info.
      if [ "${timeLeft}" -gt "90000" ]; then

         emailErrorInfo+="\n$i\n"
         emailErrorInfo+="Last FULL backup is over 25 hours old!!\n"
         sendEmail=true
      fi

      #If a terminal is being run, we print the results thus far, for debugging purposes.
      if [ "$isTTY" = "true" ]
      then

          printf "\nLast Backup Info\n"

          printf "${backupType}"
          printf "\n"

          printf "${lockTime}"
          printf "\n"

          printf "${exitState}"
          printf "\n"

          printf "${lastError}"
          printf "\n"

          printf "\nFull Backup Info\n"
          printf "${startTime}"
          printf "\n"

          printf "${endTime}"
          printf "\n"

          printf "\n"
      fi
   fi

done

#If the sendEmail variable has been flagged true we know we have to send an email alert.  Send mail will have to be enabled on the linux machine.
if [ "$sendEmail" = true ]; then
   /usr/local/bin/sendEmail -f mysql@"${hostname}.hostname.com" -s host.hostname.com -u "MySQL Alerts" -t "$emailaddress" -m "`printf "${emailErrorInfo}"`"
   [ "$isTTY" = "true" ] &&  printf "${emailErrorInfo}"
fi
