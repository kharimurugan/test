#!/bin/bash

HOSTNAME=`uname -n`
SAVEDATE=`date +%d%B%Y_%H%M%S`
SAVEDIR="/var/tmp/validation/precheck/postchecks.${SAVEDATE}"

echo "Started to gather postchecks info on ${HOSTNAME}.If this hangs for any longer than 30 seconds,probably worth running with ksh -x to see where script is hanging.\n"

if [ ! -d ${SAVEDIR} ]; then
 mkdir -p ${SAVEDIR}
fi

chmod 700 ${SAVEDIR}

function get_hw() {
 i_uptm=$(uptime);
 HW_INFO=$(dmidecode -t system| grep Manufacturer| cut -d ':' -f2 | sed -e 's/^[[:space:]]*//' | tr '[a-z]' '[A-Z]');
 HW_SPN=$(dmidecode -s system-product-name); 
 HW_SRLNO=$(dmidecode -s system-serial-number);
 case ${HW_INFO} in
  HP|HPE|IBM|LENOVO|DELL) 
   HW_TYPE="Physical Server"; 
   HW_BOL=0;
   ;;
  VM*)
   HW_TYPE="Virtual Machine"; 
   HW_BOL=1;
   ;;
   *)
   HW_TYPE="Unable to find"; 
   HW_BOL=1;
   ;;
 esac
}

function get_wwpn_fxn() {
 echo "Collecting ............FC Port information"
 wf_fchost=$(systool -c fc_host -A port_name | grep "Class Device" | awk -F '=' '{print $2}' | tr -d '"');
 wf_arrlen=${#wf_fchost[@]};
 if [ "${wf_arrlen}" -gt "0" ]; then
  echo -e "Hardware type: ${HW_INFO}\nSerial Number: ${HW_SRLNO}" > "${SAVEDIR}/FC_port.out";
  echo -e "Host-adapter\t Slot no:\t\tPort no:\t HBA WWN\t\t Speed\n------------\t --------\t\t--------\t --------\t\t --------" >> "${SAVEDIR}/FC_port.out";
  for tmp_host in `seq $wf_arrlen`; do
    systool -c fc_host -v -d ${wf_fchost[tmp_host-1]} > "${BF_tmppath_temp}.wwpn_infotmp";
    fc_slot_id=$(grep -w "Device path" "${BF_tmppath_temp}.wwpn_infotmp" | grep -v "Class Device path" | awk -F '/' '{print $5}');
    fc_port=$(grep -w "Device path" "${BF_tmppath_temp}.wwpn_infotmp" | grep -v "Class Device path" | awk -F '/' '{print $6}');
    fc_slot_name=$(dmidecode | grep -i $(echo $fc_port | awk -F '.' '{print $1}') -B 10 | grep -w "Designation:" | awk -F 'PCI-E' '{print $2}');
    fc_wwpn=$(grep -w "port_name" "${BF_tmppath_temp}.wwpn_infotmp" | awk -F '=' '{print $2}' | tr -d '"');
    fc_speed=$(systool -c scsi_host -v -d ${wf_fchost[tmp_host-1]} | grep -w info | awk -F '=' '{print $2}' | tr -d '"');
    echo -e $(grep -v "zZzZ" /sys/class/scsi_host/${wf_fchost[tmp_host-1]}/modeln*)"\t${fc_slot_name} (${fc_slot_id})\t$fc_port\t$fc_wwpn\t$fc_speed" >> "${SAVEDIR}/FC_port.out";
  done;
 else echo -e "NO FC card found!!!" > "${SAVEDIR}/FC_port.out"; fi;
}

function get_emcinfo() {
 echo "Collecting ............powermt display"
 if [ "${HW_BOL}" == "0" ]; then
  which powermt >/dev/null 2>&1; POW_MT_CMD=$?;
  if [ "${POW_MT_CMD}" == "0" ]; then
   powermt display > ${SAVEDIR}/powermt.out 2>/dev/null
   powermt display dev=all >> ${SAVEDIR}/powermt.out 2>/dev/null
  else
   echo -e "powermt not found" > ${SAVEDIR}/powermt.out
  fi
 else
  echo -e "powermt not found" > ${SAVEDIR}/powermt.out
 fi
}

function get_oracle_asm() {
echo "Collecting ............Oracle ASM/UDEV Disk Information"
if [ "${HW_BOL}" == "0" ]; then
 CHECK_ASM_PMON=`ps -ef | grep -i asm_pmon | grep -v grep | wc -l`
 CHECK_ORA_PMON=`ps -ef | grep -i ora_pmon | grep -v grep | wc -l`
  if [ "${CHECK_ASM_PMON}" != "0" ] && [ "${CHECK_ORA_PMON}" != "0" ]; then
   for AS_FILNAME in $( grep -i emcpower /etc/udev/rules.d/*.rules | grep -i "oracle" | awk -F ":" '{print $1}' | sort -u );
    do
     if [ -f ${AS_FILNAME} ]; then
      output=`grep -i emcpower ${AS_FILNAME} | egrep -v ^# | awk -F',' '{print $1}' | awk -F'=' '{print $3}' | tr -d '"' | wc -l`
       if [ "${output}" != "0" ];then
        for output1 in `grep -i emcpower ${AS_FILNAME} | egrep -v ^# | awk -F',' '{print $1}' | awk -F'=' '{print $3}' | tr -d '"' | uniq | grep -v "^[[:space:]]*$"`
         do
          DISKOWNER=`grep -i $output1 ${AS_FILNAME} | egrep -v ^# | awk -F',' '{print $2}'| awk -F'=' '{print $2}' | tr -d '"' | grep -v "^[[:space:]]*$"`
          DISKGRP=`grep -i $output1 ${AS_FILNAME} | egrep -v ^# | awk -F',' '{print $3}'| awk -F'=' '{print $2}' | tr -d '"' | grep -v "^[[:space:]]*$"`
          TEMP1=`ls -ld /dev/$output1 | awk '{print $3}'`
          TEMP2=`ls -ld /dev/$output1 | awk '{print $4}'`
           if [ "$TEMP1" == "$DISKOWNER" ] && [ "$TEMP2" == "$DISKGRP" ]; then
            echo "$AS_FILNAME:$output1:$TEMP1:$TEMP2: ASM disk configured properly." >> ${SAVEDIR}/oracle_asm_disk.out
           else
            echo "$AS_FILNAME:$output1:$TEMP1:$TEMP2: ASM disk is not configured properly." >> ${SAVEDIR}/oracle_asm_disk.out
           fi
         done
       else
        echo "${AS_FILNAME} is empty" >> ${SAVEDIR}/oracle_asm_disk.out
       fi
     else
      echo "unable to find oracle.rules file" >> ${SAVEDIR}/oracle_asm_disk.out
     fi
   done  
  else
   echo "asm not configured in the server" >> ${SAVEDIR}/oracle_asm_disk.out
  fi
fi

if [ "${HW_BOL}" == "1" ]; then
 CHECK_ASM_PMON=`ps -ef | grep -i asm_pmon | grep -v grep | wc -l`
 CHECK_ORA_PMON=`ps -ef | grep -i ora_pmon | grep -v grep | wc -l`
  if [ "${CHECK_ASM_PMON}" != "0" ] && [ "${CHECK_ORA_PMON}" != "0" ]; then
   for AS_FILNAME in $( grep -i oracle /etc/udev/rules.d/*.rules | grep -i "oracle" | awk -F ":" '{print $1}' | sort -u );
    do
     if [ -f ${AS_FILNAME} ]; then
      output=`grep -i oracle ${AS_FILNAME} | egrep -v ^# | awk -F',' '{print $1}' | awk -F'=' '{print $3}' | tr -d '"' | wc -l`
       if [ "${output}" != "0" ];then
        for output1 in `grep -i oracle ${AS_FILNAME} | egrep -v ^# | awk -F',' '{print $1}' | awk -F'=' '{print $3}' | tr -d '"' | uniq | grep -v "^[[:space:]]*$"`
         do
          tmpx_output1=`echo $output1 | sed 's/[0-9]*//g'`
          DISKOWNER=`grep -i $output1 ${AS_FILNAME} | egrep -v ^# | awk -F',' '{print $6}'| awk -F'=' '{print $2}' | tr -d '"' | grep -v "^[[:space:]]*$"`
          DISKGRP=`grep -i $output1 ${AS_FILNAME} | egrep -v ^# | awk -F',' '{print $7}'| awk -F'=' '{print $2}' | tr -d '"' | grep -v "^[[:space:]]*$"`
          FIND_ISCSI_NAME=`ls -l /dev/disk/by-path/ | grep -i -A1 ${tmpx_output1} | tail -n 1 | awk '{print $11}' | awk -F'/' '{print $3}'`
          TEMP1=`ls -ld /dev/$FIND_ISCSI_NAME | awk '{print $3}'`
          TEMP2=`ls -ld /dev/$FIND_ISCSI_NAME | awk '{print $4}'`
           if [ "$TEMP1" == "$DISKOWNER" ] && [ "$TEMP2" == "$DISKGRP" ]; then
            echo "$AS_FILNAME:$output1:$TEMP1:$TEMP2: ASM disk configured properly." >> ${SAVEDIR}/oracle_asm_disk.out
           else
            echo "$AS_FILNAME:$output1:$TEMP1:$TEMP2: ASM disk is not configured properly." >> ${SAVEDIR}/oracle_asm_disk.out
           fi
         done
       else
        echo "${AS_FILNAME} is empty" >> ${SAVEDIR}/oracle_asm_disk.out
       fi
     else
      echo "unable to find oracle.rules file" >> ${SAVEDIR}/oracle_asm_disk.out
     fi
   done  
  else
   echo "asm not configured in the server" >> ${SAVEDIR}/oracle_asm_disk.out
  fi
fi
}

function get_time_zone() {
echo "Collecting .............Time Zone"
date | awk '{print $5}' > ${SAVEDIR}/timezone
}

function get_file_system() {
echo "Collecting ............/etc/filesystems"
cat /etc/filesystems > ${SAVEDIR}/filesystems
}

function get_inittab_7() {
echo "Collecting ............/etc/inittab and systemctl get-default"
cat /etc/inittab > ${SAVEDIR}/inittab
systemctl get-default  >> ${SAVEDIR}/inittab
}

function get_inittab_common() {
echo "Collecting ............/etc/inittab and systemctl get-default"
cat /etc/inittab > ${SAVEDIR}/inittab
}

function get_motd() {
echo "Collecting ............/etc/motd"
cat /etc/motd > ${SAVEDIR}/motd
}

function get_exports() {
echo "Collecting ............/etc/exports"
if [ -f /etc/exports ]; then
  EXPORTS=`cat /etc/exports | wc -l` 
   if [ ${EXPORTS} == "0" ]; then
    echo " No entry in /etc/exports " > ${SAVEDIR}/exports
   else
    cat /etc/exports > ${SAVEDIR}/exports
   fi
else
 echo " There is no file /etc/exports " > ${SAVEDIR}/exports
fi
}

function get_netstat() {
echo "Collecting ............Routing table"
netstat -rn    > ${SAVEDIR}/netstat_r.out
}

function get_df() {
echo "Collecting ............DF output"
egrep -vw "^Filesystem|^tmpfs|^cdrom|^sysfs|^sunrpc|^devtmpfs|^devpts|^none|^proc|^gvfs" /proc/mounts | sort | awk '{print $1"\t"$2}' > ${SAVEDIR}/df.out
}

function get_hostname() {
echo "Collecting ............hostname "
hostname         > ${SAVEDIR}/hostname.out
}

function get_uname() {
echo "Collecting ............uname -n"
uname -n         > ${SAVEDIR}/uname_n.out
}

function get_lvm() {
echo "Collecting ............pvs"
pvs         > ${SAVEDIR}/pvs.out

echo "Collecting ............vgs"
vgs         > ${SAVEDIR}/vgs.out

echo "Collecting ............lvs"
lvs         > ${SAVEDIR}/lvs.out
}

function get_ipaddr() {
echo "Collecting ............IP info"
/sbin/ip addr show | sed -n '/valid_lft/!p'  > ${SAVEDIR}/ifconfig_a.out
}

function get_runlevel() {
echo "Collecting ............Runlevel info"
runlevel >  ${SAVEDIR}/runlevel.out
}

function get_redhat_release() {
echo "Collecting ............Redhat release"
cat /etc/redhat-release >  ${SAVEDIR}/release.out
}

function get_suse_release() {
echo "Collecting ............Redhat release"
cat /etc/SuSE-release >  ${SAVEDIR}/release.out
}

function get_resolv() {
echo "Collecting ............resolv.conf"
cat /etc/resolv.conf >  ${SAVEDIR}/resolvconf.out
}

function get_hosts() {
echo "Collecting ............hosts"
cat /etc/hosts >  ${SAVEDIR}/hosts.out
}

function get_grub2() {
echo "Collecting ............grub2.conf"
cat /boot/grub2/grub.cfg >  ${SAVEDIR}/grub.out
}

function get_grub_common() {
echo "Collecting ............grub.conf"
cat /boot/grub/grub.conf > ${SAVEDIR}/grub.out
}

function get_suse_grub() {
echo "Collecting ............grub.conf"
cat /boot/grub/menu.lst > ${SAVEDIR}/grub.out
}

function get_rpm() {
echo "Collecting .........rpmlist"
rpm -qa  >  ${SAVEDIR}/rpm.out
}

function get_fstab() {
echo "Collecting ............fstab"
cat /etc/fstab >  ${SAVEDIR}/fstab.out
}

function get_mem() {
echo "Collecting ............SwapTotal"
cat /proc/meminfo  | grep -i SwapTotal >  ${SAVEDIR}/swap_total.out

echo "Collecting ............MemoryTotal"
cat /proc/meminfo  | grep -i MemTotal >  ${SAVEDIR}/Memory_total.out
}

function get_network_adapter() {
echo "Collecting ............Network Adapter info"
lspci | egrep -i 'network|ethernet' >  ${SAVEDIR}/Network_Adapter.out
}

function get_systemctl() {
echo "Collecting ............chkconfig/systemctl details"
systemctl list-units --type service >  ${SAVEDIR}/chkconfig.out
chkconfig --list >>  ${SAVEDIR}/chkconfig.out
}

function get_chkconfig() {
echo "Collecting ............chkconfig/systemctl details"
chkconfig --list >  ${SAVEDIR}/chkconfig.out
}

function get_ntp() {
echo "Collecting ............/etc/ntp configuration"
if [ -f /usr/sbin/ntpq ]; then
	/usr/sbin/ntpq -p | awk '{print $1,$2}' > ${SAVEDIR}/ntpstat.out 2>/dev/null
fi
}

function get_redhat_cluster() {
echo "Collecting ............Redhat Cluster information"
if [ -f /usr/sbin/clustat ]; then
  /usr/sbin/clustat > ${SAVEDIR}/redhat_cluster.out
else
  echo "This is not a redhat cluster server" > ${SAVEDIR}/redhat_cluster.out
fi
}

function get_veritas_cluster() {
echo "Collecting ............Veritas Cluster information"
if [ -f /opt/VRTS/bin/hastatus ]; then
  /opt/VRTS/bin/hastatus -summary > ${SAVEDIR}/veritas_cluster.out 2>/dev/null
else
  echo "This is not a veritas cluster" > ${SAVEDIR}/veritas_cluster.out
fi
}

function get_crontab() {
echo "Collecting ............crontab Information"
crontab -l > ${SAVEDIR}/crontab.out 2>/dev/null
}

function get_profile() {
echo "Collecting ............/etc/profile"
cat /etc/profile > ${SAVEDIR}/profile.out 2>/dev/null
}

function get_group() {
echo "Collecting ............/etc/group"
cat /etc/group > ${SAVEDIR}/group.out 2>/dev/null
}

function compare(){
 echo "$1 - Checking and comparing $2 file ... "
 diff  $OLDDIR/$2 $NEWDIR/$2
 RESULT=`echo $?`
 if [[ $RESULT -ge 1 ]] ; then
  echo "+++++++++++++++++++++++++++++$3+++++++++++++++++++++++++++++"  >> "$TMPLOGFILE"
  echo "" >> "$TMPLOGFILE"
  diff  $OLDDIR/$2 $NEWDIR/$2 >> "$TMPLOGFILE"
  echo "" >> "$TMPLOGFILE"
 else
  diff  $OLDDIR/$2 $NEWDIR/$2 >> "$TMPLOGFILE"
 fi
 if [[ $RESULT -ge 1 ]] ; then
  printf "%20s %30s %30s %20s \n" $1 $3 "Data_Mismatch"  >> "$LOGFILE"
 else
  printf "%20s %30s %30s %20s \n" $1 $3 "No_Differences_Found"   >> "$LOGFILE"
 fi
}

function funct_checkout() {
echo "===================================================================================="
echo "Completed checkout data collection. Check the following for information:${SAVEDIR}  "
echo "===================================================================================="

START_DATE=`date`
STARTTIME=$(date +%s)
Program_Version="1.0"
DATE=`date "+%d-%b-%Y-%H-%M"`
SERVER=`uname -n`
LOGDIR="/var/tmp/validation/PREPOST_REPORT"
LOGFILE="$LOGDIR/$SERVER"_"$DATE""_compare_report.txt"
TMPLOGFILE="$LOGDIR/tmp_compare_report.txt"
HOST=`hostname -s`

if [ ! -d ${LOGDIR} ]; then
 mkdir -p ${LOGDIR}
fi

cp /dev/null $LOGFILE
cp /dev/null $MAILREPORT
cp /dev/null $TMPLOGFILE

USERID=`echo $USER`

if [ -z "$USERID" ]
then
   echo  "You must run this script as Root user\n"
   exit 1
fi

##############################
###Cleaning report directories if number of directories count is more than 4
#############################

COMPAR_COUNT=`ls -ltr /var/tmp/validation/PREPOST_REPORT | grep -v tmp_compare | wc -l`
while [ ${COMPAR_COUNT} -gt 4 ]
do
 OLD_DATA=`ls -ltr /var/tmp/validation/precheck/postchecksPREPOST_REPORT | grep -v tmp_compare | grep -v total | head -1 | awk '{print $9}'`
 FOLDER="/var/tmp/validation/PREPOST_REPORT/${OLD_DATA}"
 echo "$FOLDER"
 rm -rf $FOLDER
 COMPAR_COUNT=`ls -ltr /var/tmp/validation/PREPOST_REPORT | grep -v tmp_compare | grep -v total | wc -l`
done

######################################################################
########################Validating the old data count#################

OLD_DIR=( $(ls -lrt /var/tmp/validation/precheck | grep -i prechecks. | awk '{print $9}' | tail -4) );
File_count=`ls -lrt /var/tmp/validation/precheck/${OLD_DIR[3]} | wc -l`
if [ $File_count -ge 10 ]; then
 echo "Number of files in ${OLD_DIR[3]} is $File_count"
 OLDDIR=/var/tmp/validation/precheck/${OLD_DIR[3]}
else
 echo "No Valide data in latest Precheck direcory ${OLD_DIR[3]} and number of files in it is $File_count"
File_count=`ls -lrt /var/tmp/validation/precheck/${OLD_DIR[2]} | wc -l`
if [ $File_count -ge 10 ]; then
 echo "Number of files in ${OLD_DIR[2]} is $File_count"
 OLDDIR=/var/tmp/validation/precheck/${OLD_DIR[2]}
else
 echo "No Valide data in latest Precheck direcory ${OLD_DIR[2]} and number of files in it is $File_count"
 File_count=`ls -lrt /var/tmp/validation/precheck/${OLD_DIR[1]} | wc -l`
if [ $File_count -ge 10 ]; then
 echo "Number of files in ${OLD_DIR[1]} is $File_count"
 OLDDIR=/var/tmp/validation/precheck/${OLD_DIR[1]}
else
 echo "No Valide data in latest Precheck direcory ${OLD_DIR[1]} and number of files in it is $File_count"
File_count=`ls -lrt /var/tmp/validation/precheck/${OLD_DIR[0]} | wc -l`
if [ $File_count -ge 10 ]; then
 echo "Number of files in ${OLD_DIR[0]} is $File_count"
 OLDDIR=/var/tmp/validation/precheck/${OLD_DIR[0]}
else
 echo "No Valide data in latest Precheck direcory ${OLD_DIR[0]} and number of files in it is $File_count"
 exit 1
fi
fi
fi
fi

echo  "the Location of Pre-Reboot  Directory : $OLDDIR" 

NEWDIR=/var/tmp/validation/precheck/`ls -lrt /var/tmp/validation/precheck | grep -i postchecks. | awk '{print $9}' | tail -1`
echo  "the Location of Post-Reboot Directory : $NEWDIR"
sleep 5



echo "Validated on `date`" > "$LOGFILE"
echo "PRE-REBOOT DIR  - $OLDDIR"  >> "$LOGFILE"
echo "POST-REBOOT DIR  - $NEWDIR" >> "$LOGFILE"
echo "\n" >> "$LOGFILE"
echo "\n" >> "$LOGFILE"
echo "\n"
echo "========================================================================================"  >> "$LOGFILE"
echo "========================================================================================"  > "$TMPLOGFILE"
echo "Detailed Information on the differences found after validation as below"  >> "$TMPLOGFILE"
echo "========================================================================================"  >> "$TMPLOGFILE"

#functions to check the previous and newer outputs

compare	01	group.out	GROUP
compare	02	profile.out	PROFILE
compare	03	crontab.out	CRONTAB
compare	04	oracle_asm_disk.out	ORACLE_ASM_DISK
compare	05	veritas_cluster.out	VERITAS_CLUSTER
compare	06	redhat_cluster.out	REDHAT_CLUSTER
compare	07	FC_port.out	FC_PORT
compare	08	powermt.out	POWERMT
compare	09	chkconfig.out	CHKCONFIG
compare	10	Network_Adapter.out	NETWORK_ADAPTER
compare	11	Memory_total.out	MEMORY_TOTAL
compare	12	swap_total.out	SWAP_TOTAL
compare	13	fstab.out	ETC_FSTAB
#compare	14	rpm.out	RPM_QA#
compare	15	grub.out	GRUB
compare	16	hosts.out	HOSTS
compare	17	resolvconf.out	ETC_RESOLV_CONF
compare	18	release.out	RELEASE
compare	19	runlevel.out	RUNLEVEL
compare	20	ifconfig_a.out	IFCONFIG
compare	21	lvs.out	LVS
compare	22	vgs.out	VGS
compare	23	pvs.out	PVS
compare	24	uname_n.out	UNAME
compare	25	hostname.out	HOSTNAME
compare	26	df.out	DF
compare	27	netstat_r.out	NETSTAT_R
compare	28	exports	ETC_EXPORTS
compare	29	motd	MOTD
compare	30	inittab	ETC_INITTAB
compare	31	filesystems	ETC_FILESYSTEMS
compare	32	timezone	TIME_ZONE



#########################################################
cat $TMPLOGFILE >> $LOGFILE
echo "\n" >> $LOGFILE
echo "\n Check the Log in $LOGFILE"
#########################################################
}

function exit_status() {
EXIT_STATUS=$( grep -i mismatch ${LOGFILE} | wc -l)
if [ "${EXIT_STATUS}" != "0" ]; then
 exit 1
else
 exit 0
fi
}

function do_rhel7() {
get_time_zone;
get_file_system;
get_inittab_7;
get_motd;
get_exports;
get_netstat;
get_df;
get_hostname;
get_uname;
get_lvm;
get_ipaddr;
get_runlevel;
get_redhat_release;
get_resolv;
get_hosts;
get_grub2;
#get_rpm;
get_fstab;
get_mem;
get_network_adapter;
get_systemctl;
get_emcinfo;
get_wwpn_fxn;
get_redhat_cluster;
get_veritas_cluster;
get_oracle_asm;
get_crontab;
get_profile;
get_group;
}

function do_rhel_common() {
get_time_zone;
get_file_system;
get_inittab_common;
get_motd;
get_exports;
get_netstat;
get_df;
get_hostname;
get_uname;
get_lvm;
get_ipaddr;
get_runlevel;
get_redhat_release;
get_resolv;
get_hosts;
get_grub_common;
#get_rpm;
get_fstab;
get_mem;
get_network_adapter;
get_chkconfig;
get_emcinfo;
get_wwpn_fxn;
get_redhat_cluster;
get_veritas_cluster;
get_oracle_asm;
get_crontab;
get_profile;
get_group;
}

function do_rhel_suse() {
get_time_zone;
get_file_system;
get_inittab_common;
get_motd;
get_exports;
get_netstat;
get_df;
get_hostname;
get_uname;
get_lvm;
get_ipaddr;
get_runlevel;
get_suse_release;
get_resolv;
get_hosts;
get_suse_grub;
#get_rpm;
get_fstab;
get_mem;
get_network_adapter;
get_chkconfig;
get_emcinfo;
get_wwpn_fxn;
get_redhat_cluster;
get_veritas_cluster;
get_oracle_asm;
get_crontab;
get_profile;
get_group;
}

function main_fnx() {
 if [ -f /etc/redhat-release ]; then
  rels_detail=$(sed '/^$/d' /etc/redhat-release | head -1); 
  OS_ver=$(echo ${rels_detail} | sed 's/.*release\ //' | awk '{print $1}');
  RHEL_VER=$(echo ${OS_ver}| awk -F '.' '{print $1}' | tr -d '\n' | tr -d '\r' | tail -c 1); 
  OS_ver="RHEL ${OS_ver}";
  if [ "${RHEL_VER}" -eq "7" ]; then 
   do_rhel7;
   funct_checkout;
   exit_status;
  elif [ "${RHEL_VER}" -lt "7" ]; then 
   do_rhel_common;
   funct_checkout;
   exit_status;
  elif [ -f /etc/SuSE-release ]; then
   rels_detail=$(sed '/^$/d' /etc/SuSE-release | grep -i suse | head -1); 
   OS_ver=$(echo ${rels_detail} | awk '{print "SUSE" $7}');
   do_rhel_suse;
   funct_checkout;
   exit_status
  else 
   OS_ver="Not an RHEL or SUSE server";
   do_rhel_common;
   funct_checkout;
   exit_status;
  fi;
 fi;
}
get_hw;
main_fnx;
