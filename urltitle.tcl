# Script to grab titles from webpages
# Updated version by teel @ IRCnet
#
# https://github.com/teeli/urltitle
#
# Detects URL from IRC channels and prints out the title
#
# Version Log:
# 0.07     Added Content-Type check (text/html only) and exceptino handling for tDom with a fallback to
#          regexp if tDom fails.
# 0.06     Added XPATH support to title parsing (only if tdom package is available)
# 0.05     Added SNI support for TLS (with TLS version check)
# 0.04     HTML parsing for titles added
# 0.03c    HTTPS support is now optional and will be automatically dropeed if TCL TSL package does not exist
# 0.03b    Some formatting
# 0.03     HTTPS support
# 0.02     Updated version by teel. Added support for redirects, trimmed titles (remove extra whitespaces),
#          some optimization
# 0.01a    Original version by rosc
#
################################################################################################################
#
# Original script:
# Copyright C.Leonhardt (rosc2112 at yahoo com) Aug.11.2007
# http://members.dandy.net/~fbn/urltitle.tcl.txt
# Loosely based on the tinyurl script by Jer and other bits and pieces of my own..
#
################################################################################################################
#
# Usage:
#
# 1) Set the configs below
# 2) .chanset #channelname +urltitle        ;# enable script
# 3) .chanset #channelname +logurltitle     ;# enable logging
# Then just input a url in channel and the script will retrieve the title from the corresponding page.
#
################################################################################################################

namespace eval UrlTitle {
  # CONFIG
  set ignore "bdkqr|dkqr"   ;# User flags script will ignore input from
  set length 5              ;# minimum url length to trigger channel eggdrop use
  set delay 1               ;# minimum seconds to wait before another eggdrop use
  set timeout 5000          ;# geturl timeout (1/1000ths of a second)

  # BINDS
  bind pubm "-|-" {*://*} UrlTitle::handler
  setudef flag urltitle               ;# Channel flag to enable script.
  setudef flag logurltitle            ;# Channel flag to enable logging of script.

  # INTERNAL
  set last 1                ;# Internal variable, stores time of last eggdrop use, don't change..
  set scriptVersion 0.06

  # PACKAGES
  package require http                ;# You need the http package..
  if {[catch {set tlsVersion [package require tls]}]} {
    set httpsSupport false
  } else {
    set httpsSupport true
    if {[package vcompare $tlsVersion 1.6.4] < 0} {
      putlog "UrlTitle: TCL TLS version 1.6.4 or newer is required for proper https support (SNI)"
    }
  }
  if {[catch {package require htmlparse}]} {
    set htmlSupport false
  } else {
    set htmlSupport true
  }
  if {[catch {package require tdom}]} {
    set tdomSupport false
  } else {
    set tdomSupport true
  }

  # Enable SNI support for TLS if suitable TLS version is installed
  proc socket {args} {
    variable tlsVersion
    set opts [lrange $args 0 end-2]
    set host [lindex $args end-1]
    set port [lindex $args end]

    if {[package vcompare $tlsVersion 1.7.11] >= 0} {
      # tls version 1.7.11 should support autoservername
      ::tls::socket -autoservername true {*}$opts $host $port
    } elseif {[package vcompare $tlsVersion 1.6.7] >= 0} {
      # From version 1.6.7, it shouldn't be necessary to specify any ciphers.
      ::tls::socket -servername $host {*}$opts $host $port
    } elseif {[package vcompare $tlsVersion 1.6.4] >= 0} {
      ::tls::socket -ssl3 false -ssl2 false -tls1 true -servername $host {*}$opts $host $port
    } else {
      # default fallback without servername (SNI certs will not work)
      ::tls::socket -ssl3 false -ssl2 false -tls1 true {*}$opts $host $port
    }
  }

  proc handler {nick host user chan text} {
    variable httpsSupport
    variable htmlSupport
    variable delay
    variable last
    variable ignore
    variable length
    set unixtime [clock seconds]
    if {[channel get $chan urltitle] && ($unixtime - $delay) > $last && (![matchattr $user $ignore])} {
      foreach word [split $text] {
        if {[string length $word] >= $length && [regexp {^(f|ht)tp(s|)://} $word] && \
            ![regexp {://([^/:]*:([^/]*@|\d+(/|$))|.*/\.)} $word]} {
          set last $unixtime
          # enable https if supported
          if {$httpsSupport} {
            ::http::register https 443 [list UrlTitle::socket]
          }
          set urtitle [UrlTitle::parse $word]
          if {$htmlSupport} {
            set urtitle [::htmlparse::mapEscapes $urtitle]
          }
          # unregister https if supported
          if {$httpsSupport} {
            ::http::unregister https
          }
          if {[string length $urtitle]} {
            putserv "PRIVMSG $chan :Title: $urtitle"
          }
          break
        }
      }
    }
    # change to return 0 if you want the pubm trigger logged additionally..
    return 1
  }

  proc parse {url} {
    variable timeout
    variable tdomSupport
    set title ""
    if {[info exists url] && [string length $url]} {
      if {[catch {set http [::http::geturl $url -timeout $timeout]} results]} {
        putlog "Connection to $url failed"
      } else {
        if { [::http::status $http] == "ok" } {
          set data [::http::data $http]
          set status [::http::code $http]
          array set meta [::http::meta $http]
          # only parse html files for titles
          if { [string first "text/html" $meta(Content-Type)] >= 0 } {
            switch -regexp -- $status {
              "HTTP.*200.*" {
                if {$tdomSupport} {
                  # use XPATH if tdom is supported
                  if {[catch {set doc [dom parse -html -simple $data]} results]} {
                    # fallback to regex parsing if tdom fails
                    regexp -nocase {<title.*>(.*?)</title>} $data match title
                    set title [regsub -all -nocase {\s+} $title " "]
                  } else {
                    # parse dom
                    set root [$doc documentElement]
                    set title [[$root selectNodes {//head/title/text()}] data]
                  }
                } else {
                  # fallback to regex parsing if tdom is not enabled
                  regexp -nocase {<title.*>(.*?)</title>} $data match title
                  set title [regsub -all -nocase {\s+} $title " "]
                }
              }
              "HTTP\/[0-1]\.[0-1].3.*" {
                catch {set title [UrlTitle::parse $meta(location)]} error
              }
            }
          }
        } else {
          putlog "Connection to $url failed"
        }
        ::http::cleanup $http
      }
    }
    return $title
  }


  putlog "Initialized Url Title Grabber v$scriptVersion"
}
