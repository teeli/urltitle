# Script to grab titles from webpages
# Updated version by teel @ IRCnet
#
# https://github.com/teeli/urltitle
#
# Detects URL from IRC channels and prints out the title
#
# Version Log:
# 0.12     Added a list of URL to ignore as regex (thanks to astrorigin on github for the pull request)
# 0.11     Updated regex parser to only parse titles inside <head> tags
#          Added HTTP error status logging
# 0.10     Fixed XPath parsing error and added regex fallback if XPath fails
# 0.09     HTTPs redirects, case-insensitive HTTP header fix, other small bug fixes
# 0.08     Changed putserv to puthelp to queue the messages
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
  variable ignore "bdkqr|dkqr" ;# User flags script will ignore input from
  variable length 5            ;# minimum url length to trigger channel eggdrop use
  variable delay 1             ;# minimum seconds to wait before another eggdrop use
  variable timeout 5000        ;# geturl timeout (1/1000ths of a second)
  variable fetchLimit 5        ;# How many times to process redirects before erroring
  variable urlignore           ;# Url patterns to ignore
  set urlignore [list \
    #{://www\.youtube\.com} \
    #{://youtu\.be} \
  ]

  # BINDS
  bind pubm "-|-" {*://*} UrlTitle::handler
  setudef flag urltitle        ;# Channel flag to enable script.
  setudef flag logurltitle     ;# Channel flag to enable logging of script.

  # INTERNAL
  variable last 1              ;# Internal variable, stores time of last eggdrop use, don't change..
  variable scriptVersion 0.12

  # PACKAGES
  package require http         ;# You need the http package..
  variable httpsSupport false
  variable htmlSupport false
  variable tdomSupport false
  if {![catch {variable tlsVersion [package require tls]}]} {
    set httpsSupport true
    if {[package vcompare $tlsVersion 1.6.4] < 0} {
      putlog "UrlTitle: TCL TLS version 1.6.4 or newer is required for proper https support (SNI)"
    }
  }
  if {![catch {package require htmlparse}]} {
    set htmlSupport true
  }
  if {![catch {package require tdom}]} {
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
            ![regexp {://([^/:]*:([^/]*@|\d+(/|$))|.*/\.)} $word] && \
            ![urlisignored $word]} {
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
          if {$urtitle eq ""} {
            break
          }
          if {[string length $urtitle]} {
            puthelp "PRIVMSG $chan :Title: $urtitle"
          }
          break
        }
      }
    }
    # change to return 0 if you want the pubm trigger logged additionally..
    return 1
  }

  # General HTTP redirect handler
  proc Fetch {url args} {
    variable fetchLimit
    for {set count 0} {$count < $fetchLimit} {incr count} {
      set token [::http::geturl $url {*}$args]
      if {[::http::status $token] ne "ok" || ![string match 3?? [::http::ncode $token]]} {
        break
      }
      set meta [::http::meta $token]
      if {[dict exists $meta Location]} {
        set url [dict get $meta Location]
      }
      if {[dict exists $meta location]} {
        set url [dict get $meta location]
      }
      ::http::cleanup $token
    }
    return $token
  }

  proc parseTitleXPath {data} {
    set title ""
    if {[catch {set doc [dom parse -html -simple $data]} results]} {
      # fallback to regex parsing if tdom fails
      set title [parseTitleRegex $data]
    } else {
      # parse dom
      set root [$doc documentElement]
      set node [$root selectNodes {//head/title/text()}]
      if {$node != ""} {
        # return title if XPath was able to parse it
        set title [$node data]
      } else {
        # Fallback to regex if XPath failed
        set title [parseTitleRegex $data]
      }
    }
  }

  proc parseTitleRegex {data} {
    set title ""
    # fallback to regex parsing if tdom fails
    regexp -nocase {<head>.*<title.*>(.*?)</title>.*</head>} $data match title
    set title [regsub -all -nocase {\s+} $title " "]
    return $title
  }

  proc parse {url} {
    variable timeout
    variable tdomSupport
    set title ""
    if {[info exists url] && [string length $url]} {
      if {[catch {set http [Fetch $url -timeout $timeout]} results]} {
        putlog "Connection to $url failed"
        putlog "Error: $results"
      } else {
        if { [::http::status $http] == "ok" } {
          set data [::http::data $http]
          set status [::http::code $http]
          set meta [::http::meta $http]

          # only parse html files for titles
          if {
            ([dict exists $meta Content-Type] && [string first "text/html" [dict get $meta Content-Type]] >= 0) ||
            ([dict exists $meta content-type] && [string first "text/html" [dict get $meta content-type]] >= 0)
          } {
            switch -regexp -- $status {
              "HTTP.*200.*" {
                if {$tdomSupport} {
                  # use XPATH if tdom is supported
                  set title [parseTitleXPath $data]
                } else {
                  # fallback to regex parsing if tdom is not enabled
                  set title [parseTitleRegex $data]
                }
              }
              "HTTP\/[0-1]\.[0-1].3.*" {
                if {[dict exists $meta Location]} {
                  set title [UrlTitle::parse [dict get $meta Location]]
                }
                if {[dict exists $meta location]} {
                  set title [UrlTitle::parse [dict get $meta location]]
                }
              }
              default {
                putlog "Error: $status ($url)"
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

  proc urlisignored {word} {
    variable urlignore
    foreach url $urlignore {
      if {[regexp $url $word]} {
        return 1
      }
    }
    return 0
  }

  putlog "Initialized Url Title Grabber v$scriptVersion"
}
