#!/bin/vbash
cfg=/opt/vyatta/sbin/vyatta-cfg-cmd-wrapper
$cfg begin
$cfg load /tmp/config.boot
$cfg commit
$cfg save
$cfg end
