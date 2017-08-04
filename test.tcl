#!/usr/bin/env tclsh
###############################################################
#
# Test script for eggdrop scripts
#
###############################################################

# CONFIG
set scriptname "urltitle.tcl"
set channel "#testchannel"
set nickname "user"
set uhost "uhost"
set handle "handle"

# start script
set scriptVersion 0.1
set binds [dict create]
puts "Eggdrop script tester $scriptVersion"

proc setudef {type value} {
    puts "SETUDEF:  $type $value"
}

# handle eggdrop binds
proc bind {type perms cmd proc} {
    puts "BIND:     $type $perms $cmd $proc"
    global binds
    # create type if not exists
    if {![dict exists $binds $type]} {
        dict set binds $type [dict create]
    }
    # get existing commands of the same type
    set d [dict get $binds $type]
    # add command to dict
    dict set binds $type [dict append d $cmd $proc]
}

# output eggdrop putserv command to stdout
proc putserv {output} {
    puts "PUTSERV:  $output";
}

# output eggdrop puthelpcommand to stdout
proc puthelp {output} {
    puts "PUTHELP:  $output";
}

# output egggdrop putlog command to stdout
proc putlog {output} {
    puts "PUTLOG:   $output";
}

proc matchattr {handle flags {channel ""}} {
    return 0
}

proc channel {func name setting} {
    return 1
}

# emulate pubm binds
proc pubm {{value ""}} {
    puts "PUBM:     $value";
    global binds
    global nickname
    global channel
    global uhost
    global handle
    set pubm [dict get $binds "pubm"]
    dict for {mask proc} $pubm {
        $proc $nickname $uhost $handle $channel $value
    }
#    if {[dict exists $pubm $cmd]} {
#        set p [dict get $pubm $cmd]
#        $p $nickname $uhost $handle $channel $value
#        return
#    }
#    puts "ERROR:    $cmd does not exists in pubm";
}

# emulate public command
proc pub {cmd {value ""}} {
    puts "PUB:      $cmd $value";
    global binds
    global nickname
    global channel
    global uhost
    global handle
    set pub [dict get $binds "pub"]
    if {[dict exists $pub $cmd]} {
        set p [dict get $pub $cmd]
        $p $nickname $uhost $handle $channel $value
        return
    }
    puts "ERROR:    $cmd does not exists in pub";
}

# emulate msg command
proc msg {cmd {value ""}} {
    puts "MSG:      $cmd $value";
    global binds
    global nickname
    global uhost
    global handle
    set msg [dict get $binds "msg"]
    if {[dict exists $msg $cmd]} {
        set p [dict get $msg $cmd]
        $p $nickname $uhost $handle $value
        return
    }
    puts "ERROR:    $cmd does not exists in msg";
}

# emulate dcc command
proc dcc {cmd {value ""}} {
    puts "DCC:      $cmd $value";
    global binds
    global nickname
    global uhost
    global handle
    set dcc [dict get $binds "dcc"]
    if {[dict exists $dcc [string range $cmd 1 999]]} {
        set p [dict get $dcc [string range $cmd 1 999]]
        $p $nickname $uhost $handle $value
        return
    }
    puts "ERROR:    $cmd does not exists in dcc";
}

source $scriptname

# TESTS GO HERE
pubm "Check it out at https://github.com/teeli/urltitle"
after 5000
# multiple title tag tesst
pubm "http://www.rumba.fi/uutiset/kommentti-paskaa-suomi-iskelmaa-tekeva-kotiteollisuus-haluaa-julkisuuteen-julkaisee-levyn/"
after 5000
# SNI TLS test
pubm "https://www.rust-lang.org/en-US/"
after 5000
# SNI TLS test
pubm "https://centmin.sh/"
after 5000
# xpath test 1
pubm "https://pbs.twimg.com/media/C58JTUXXEAIbCUv.jpg"
after 5000
# xpath test 2
pubm "https://www.amazon.com/Bro-Custom-Symbol-Tees-Doggy-Yellow/dp/B01EDXDU4M/"
after 5000
# xpath test 3
pubm "http://img.fark.net/images/cache/850/W/Wt/fark_WtjCu6v522v0PIvoDm2QVLDv97U.jpg?t=3GK9fKLvopse5AD0O7kErA&f=1488776400"
after 5000
# redirect 301 test
pubm "https://www.pastebin.com/"
after 5000
# more tests from githb
pubm "http://www.google.com"
after 5000
pubm "https://www.google.com"
after 5000
pubm "http://google.com"
after 5000
pubm "https://www.google.com"
after 5000
pubm "https://twitter.com/ItMeIRL/status/893133548118564864"
after 5000

pubm "done"
