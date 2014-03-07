# Script to grab titles from webpages
# Updated version by teel @ IRCnet
# Even more updated by T-101 @ ircnet
#
# https://github.com/teeli/urltitle
#
# Detects URL from IRC channels and prints out the title
#
# Version Log:
# 0.05     T-101: added filetypes to ignore, added mapping to convert some nasty umlauts/utf to more irc-friendly
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
  set disabledfiletypes { jpg gif png txt mov mp4 avi mp3 pdf swf mp2 jpeg mpeg }       ;# filetypes that will not be looked at all

  # BINDS
  bind pubm "-|-" {*://*} UrlTitle::handler
  setudef flag urltitle               ;# Channel flag to enable script.
  setudef flag logurltitle            ;# Channel flag to enable logging of script.

  # INTERNAL
  set last 1                ;# Internal variable, stores time of last eggdrop use, don't change..
  set scriptVersion 0.05

  # PACKAGES
  package require http                ;# You need the http package..
  if {[catch {package require tls}]} {
    set httpsSupport false
  } else {
    set httpsSupport true
  }
  if {[catch {package require htmlparse}]} {
    set htmlSupport false
  } else {
    set htmlSupport true
  }

  # MAPPING
  set mappingArray {
    &nbsp; \x20 &quot; \x22 &amp; \x26 &apos; \x27 &ndash; \x2D
    &lt; \x3C &gt; \x3E &tilde; \x7E &euro; \x80 &iexcl; \xA1
    &cent; \xA2 &pound; \xA3 &curren; \xA4 &yen; \xA5 &brvbar; \xA6
    &sect; \xA7 &uml; \xA8 &copy; \xA9 &ordf; \xAA &laquo; \xAB
    &not; \xAC &shy; \xAD &reg; \xAE &hibar; \xAF &deg; \xB0
    &plusmn; \xB1 &sup2; \xB2 &sup3; \xB3 &acute; \xB4 &micro; \xB5
    &para; \xB6 &middot; \xB7 &cedil; \xB8 &sup1; \xB9 &ordm; \xBA
    &raquo; \xBB &frac14; \xBC &frac12; \xBD &frac34; \xBE &iquest; \xBF
    &Agrave; \xC0 &Aacute; \xC1 &Acirc; \xC2 &Atilde; \xC3 &Auml; \xC4
    &Aring; \xC5 &AElig; \xC6 &Ccedil; \xC7 &Egrave; \xC8 &Eacute; \xC9
    &Ecirc; \xCA &Euml; \xCB &Igrave; \xCC &Iacute; \xCD &Icirc; \xCE
    &Iuml; \xCF &ETH; \xD0 &Ntilde; \xD1 &Ograve; \xD2 &Oacute; \xD3
    &Ocirc; \xD4 &Otilde; \xD5 &Ouml; \xD6 &times; \xD7 &Oslash; \xD8
    &Ugrave; \xD9 &Uacute; \xDA &Ucirc; \xDB &Uuml; \xDC &Yacute; \xDD
    &THORN; \xDE &szlig; \xDF &agrave; \xE0 &aacute; \xE1 &acirc; \xE2
    &atilde; \xE3 &auml; \xE4 &aring; \xE5 &aelig; \xE6 &ccedil; \xE7
    &egrave; \xE8 &eacute; \xE9 &ecirc; \xEA &euml; \xEB &igrave; \xEC
    &iacute; \xED &icirc; \xEE &iuml; \xEF &eth; \xF0 &ntilde; \xF1
    &ograve; \xF2 &oacute; \xF3 &ocirc; \xF4 &otilde; \xF5 &ouml; \xF6
    &divide; \xF7 &oslash; \xF8 &ugrave; \xF9 &uacute; \xFA &ucirc; \xFB
    &uuml; \xFC &yacute; \xFD &thorn; \xFE &yuml; \xFF 
    &\#8211; \x2D &\#8212; \x2D “ \x22 ” \x2 &#8217; \x27 &\#8221; \x22 &rdquo; \x
    &\#214; \xD6 &\#Ouml; \xD6 Ö \xD6 &\#246; \xF6 &\#ouml; \xF6 ö \xF6
}

  proc handler {nick host user chan text} {
    variable httpsSupport
    variable htmlSupport
    variable delay
    variable last
    variable ignore
    variable length
    variable disabledfiletypes
    set unixtime [clock seconds]
    if {[channel get $chan urltitle] && ($unixtime - $delay) > $last && (![matchattr $user $ignore])} {
      foreach word [split $text] {
        if {[string length $word] >= $length && [regexp {^(f|ht)tp(s|)://} $word] && \
            ![regexp {://([^/:]*:([^/]*@|\d+(/|$))|.*/\.)} $word]} {

	foreach filetype $disabledfiletypes { if {[lindex [split $word .] end] == $filetype} {return 1} }

          set last $unixtime
          # enable https if supported
          if {$httpsSupport} {
            ::http::register https 443 ::tls::socket
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
		putserv "PRIVMSG $chan :\002\[URL\]\002 $urtitle"
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
    variable mappingArray
    set title ""
    if {[info exists url] && [string length $url]} {
      if {[catch {set http [::http::geturl $url -timeout $timeout]} results]} {
#        putlog "Connection to $url failed"
      } else {
        if { [::http::status $http] == "ok" } {
          set data [::http::data $http]
          set status [::http::code $http]
          set meta [::http::meta $http]
          switch -regexp -- $status {
            "HTTP.*200.*" {
		if {![regexp -nocase {<meta property="og:title" content="(.*?)"(.*?)/>} $data match title]} {
              regexp -nocase {<title>(.*?)</title>} $data match title }
              set title [regsub -all -nocase {\s+} $title " "]
            }
            "HTTP\/[0-1]\.[0-1].3.*" {
              regexp -nocase {Location\s(http[^\s]+)} $meta match location
              catch {set title [UrlTitle::parse $location]} error
            }
          }
        } else {
          putlog "Connection to $url failed"
        }
        ::http::cleanup $http
      }
    }
    return [string map $mappingArray $title]
  }

  putlog "Initialized Url Title Grabber v$scriptVersion"
}
