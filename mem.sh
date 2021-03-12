#!/bin/bash
CORES=1
while [ $# -gt 0 ]; do
    case $1 in
        -d) shift; DIR=$1
            ;;
    esac
    shift
done

MEMSZS="512 1024 2048 3072 4096"

DIR=./rund_benchmark
RAW=${DIR}/raw
mkdir -p ${RAW}
RUND_PRE=${RAW}/mem-rund
RUND_RES=${DIR}/mem-rund.dat

ID=0

calc() {
    mem=$1
    inf=$2
    vm_inf=$3
    pmap_inf=$4
    outf=$5
    pss=$6
    c_inf=$7

    l=$(tail -1 ${inf})
    mem_kb=$(echo "$mem * 1024" | bc)
    vss=$(echo $l | cut -d' ' -f2)
    rss=$(echo $l | cut -d' ' -f3)

    vm_total=$(grep MemTotal:      $vm_inf | awk '{print $2}')
    vm_free=$(grep MemFree:        $vm_inf | awk '{print $2}')
    vm_avail=$(grep MemAvailable:  $vm_inf | awk '{print $2}')
    c_total=$(grep ^Mem: $c_inf| awk '{print $2}')
    c_free=$(grep ^Mem: $c_inf| awk '{print $4}')
    c_avail=$(grep ^Mem: $c_inf| awk '{print $7}')
    # On some system we don't get memory from within the VM.
    [ -z $vm_total ] && vm_total=0
    [ -z $vm_free  ] && vm_free=0
    [ -z $vm_avail ] && vm_avail=0
    
    pmap_data=$(./util_parse_pmap.py $pmap_inf)

    echo "$mem_kb $vss $rss $vm_total $vm_free $vm_avail $pmap_data $pss $c_total $c_free $c_avail" >> $outf
}

echo "# VMSZ VSS RSS VM_TOTAL VM_FREE VM_AVAIL PMAP_EXEC PMAP_DATA PSS C_TOTAL C_FREE C_AVAIL (sizes in KB)" > ${RUND_RES}
for MEM in $MEMSZS; do
    echo "runD: $MEM MB"
	sed -i "/^default_memory =/c\default_memory = $MEM" /etc/kata-containers2/configuration.toml	
	pod=`crictl runp --runtime rund example-pod.json`
	cid=`sudo crictl create $pod ubuntu-container0.json example-pod.json`
	sudo crictl start $cid
	short_id=${pod:0:8}
        ps -o pid,vsz,rss,command -C rund-${short_id} > ${RUND_PRE}-$MEM.txt
	pid=`ps -ef | grep $pod | grep -v grep | awk '{print $2}'`
        pmap -x $pid > ${RUND_PRE}-$MEM-pmap.txt

	PSS=0
#	cat /proc/$pid/smaps | grep "^Pss"
	psses=`cat /proc/$pid/smaps | grep "^Pss" | awk '{print " "$2" "}'`
#	echo ====  $psses ==========
	for i in $psses; do
		PSS=`expr $PSS + $i`
	done

	kgdb -i $pod exec "cat /proc/meminfo" >${RUND_PRE}-$MEM-vm.txt
	
	sudo  crictl exec $cid free --kilo >${RUND_PRE}-$MEM-container.txt
  	crictl stopp $pod; sudo crictl rmp $pod
  	
        calc $MEM ${RUND_PRE}-$MEM.txt ${RUND_PRE}-$MEM-vm.txt ${RUND_PRE}-$MEM-pmap.txt ${RUND_RES} $PSS ${RUND_PRE}-$MEM-container.txt
done

