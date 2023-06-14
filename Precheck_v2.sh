#!/bin/bash

HOSTNAME=`uname -n`
SAVEDATE=`date +%d%B%Y_%H%M%S`

if [ ! -d /var/opt/BESClient/MaintenanceScripts/precheck ]; then
  mkdir -p /var/opt/BESClient/MaintenanceScripts/precheck
fi

##############################
##Cleaning Precheck old data #
##############################
### Cleaning Empty or valide directory #####
for i in `ls /var/opt/BESClient/MaintenanceScripts/precheck`
 do
 ISEMPTY=`ls -l /var/opt/BESClient/MaintenanceScripts/precheck/$i | wc -l`
 if [ $ISEMPTY -le 30 ]
  then
  rm -rf /var/opt/BESClient/MaintenanceScripts/precheck/$i
 fi
done

##################################################################
# Cleaning directories if no of directories count is more than 4 #
##################################################################

COUNT=`ls -ltr /var/opt/BESClient/MaintenanceScripts/precheck | grep -i precheck | wc -l`
while [ $COUNT -gt 4 ]
do
 OLD_DATA=`ls -ltr /var/opt/BESClient/MaintenanceScripts/precheck | grep -i precheck | head -1 | awk '{print $9}'`
 FOLDER=`echo "/var/opt/BESClient/MaintenanceScripts/precheck/$OLD_DATA"`
 echo $FOLDER
 rm -rf $FOLDER
 COUNT=`ls -ltr /var/opt/BESClient/MaintenanceScripts/precheck | grep -i precheck | wc -l`
done

SAVEDIR="/var/opt/BESClient/MaintenanceScripts/precheck/prechecks.${SAVEDATE}"

echo "Started to gather prechecks info  on ${HOSTNAME}. If this hangs for any longer than 30 seconds,probably worth running with sh -x to see where script is hanging.\n"

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

function get_tar() {

# Now tar up the contents of SAVEDIR and output to SAVEDIRKEEP

SAVEDIRKEEP="/var/opt/BESClient/MaintenanceScripts/PRECHECKS/"

rm -rf ${SAVEDIRKEEP}*.tar

if [ ! -d ${SAVEDIRKEEP} ]; then
 mkdir -p ${SAVEDIRKEEP}
fi

chmod 700 ${SAVEDIRKEEP}

SAVETAR="prechecks.${HOSTNAME}.${SAVEDATE}.tar"

#tar -cvf ${SAVEDIR} 2>/dev/null > ${SAVEDIRKEEP}${SAVETAR}
tar -cvf ${SAVEDIRKEEP}${SAVETAR} ${SAVEDIR} 2>/dev/null

echo " \n "
echo "=============================================================================================="
echo "Compressed data has been stored under ${SAVEDIRKEEP} upload this file in Checkin task"
echo "=============================================================================================="

echo " \n "
echo "=============================================================================================="
echo "Compressed data has been stored under ${SAVEDIRKEEP} use this file if there is no data under /tmp after migration"
echo "=============================================================================================="
echo " \n "
echo "=============================================================================================="
echo "Completed Checkin data collection. Check the following for information:\n${SAVEDIR}"
echo "=============================================================================================="
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
   get_tar;
   exit 0; 
  elif [ "${RHEL_VER}" -lt "7" ]; then 
   do_rhel_common;
   get_tar;
   exit 0;
  elif [ -f /etc/SuSE-release ]; then
   rels_detail=$(sed '/^$/d' /etc/SuSE-release | grep -i suse | head -1); 
   OS_ver=$(echo ${rels_detail} | awk '{print "SUSE" $7}');
   do_rhel_suse;
   get_tar;
   exit 0;
  else 
   OS_ver="Not an RHEL or SUSE server";
   do_rhel_common;
   get_tar;
   exit 0; 
  fi;
 fi;
}
get_hw;
main_fnx;
