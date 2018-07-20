# Script to grab titles from webpages
# Updated version by teel @ IRCnet
#
# https://github.com/teeli/urltitle
#
# Detects URL from IRC channels and prints out the title
#
# Version Log:
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

  # BINDS
  bind pubm "-|-" {*} UrlTitle::handler
  setudef flag urltitle        ;# Channel flag to enable script.
  setudef flag logurltitle     ;# Channel flag to enable logging of script.

  # INTERNAL
  variable last 1              ;# Internal variable, stores time of last eggdrop use, don't change..
  variable scriptVersion 0.10

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
         if {[string length $word] >= $length && [regexp {((?:[a-zA-Z][\w-]+:(?:\/{1,3}|[a-zA-Z0-9%])|www\d{0,3}[.]|[a-zA-Z0-9\-]+[.][a-zA-Z]{2,4}\/?)(?:[^\s()<>]+|\(([^\s()<>]+|(\([^\s()<>]+\)))*\)){0,}(?:\(([^\s()<>]+|(\([^\s()<>]+\)))*\)|[^\s\!()\[\]{};:\'\"\.\,<>?«»“”‘’]){0,})} $word]} {
          set last $unixtime
          # enable https if supported
          if {$httpsSupport} {
            ::http::register https 443 [list UrlTitle::socket]
          }
          set urtitle [UrlTitle::parse $word]
          if {$htmlSupport} {
            set urtitle [::htmlparse::mapEscapes $urtitle]
          } else {
            # Fallback to a simple decoder if htmlparse not installed
            set urtitle [simpleHtmlDecode $urtitle]
          }

          # unregister https if supported
          if {$httpsSupport} {
            ::http::unregister https
          }
          if {$urtitle eq ""} {
            break
          }
          if {[string length $urtitle]} {
            puthelp "PRIVMSG $chan :\002$urtitle"
          }
        }
      }
    }
    # change to return 0 if you want the pubm trigger logged additionally..
    return 0
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
    regexp -nocase {<title.*>(.*?)</title>} $data match title
    set title [regsub -all -nocase {\s+} $title " "]
    return $title
  }

  proc parse {url} {
    variable timeout
    variable tdomSupport
    set title ""

    if {[info exists url] && [string length $url]} {
      if {
          ([string first "http://" $url] == -1) &&
          ([string first "https://" $url] == -1)
      } {
        set url "http://$url"
      }

      ## Some websites will display a title if an image is passed without an extension.
      regsub -nocase {(\.png|\.gif|.jpeg|\.jpg)\Z} $url {} url

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

  # Simple html decoder if htmlparse is not available
  proc simpleHtmlDecode {text} {
    set title ""
    set html_mapping {
      &lsquo; '
      &rsquo; '
      &#8217; '
      &#8211; '
      &apos; '
      &#10; " "
      &#010; " "
      &sbquo; ‚
      &ldquo; “
      &rdquo; ”
      &bdquo; „
      &dagger; †
      &Dagger; ‡
      &permil; ‰
      &lsaquo; ‹
      &rsaquo; ›
      &spades; ♠
      &clubs; ♣
      &hearts; ♥
      &diams; ♦
      &oline; ‾
      &#8592; ←
      &larr; ←
      &#8593; ↑
      &uarr; ↑
      &#8594; →
      &rarr; →
      &#8595; ↓
      &darr; ↓
      &#8598; ↖
      &nwarr; ↖
      &#8599; ↗
      &nearr; ↗
      &#8601; ↙
      &swarr; ↙
      &#8600; ↘
      &searr; ↘
      &#9650; ▲
      &#x25B2; ▲
      &#9652; ▴
      &#x25B4; ▴
      &#9654; ▶
      &#x25B6; ▶
      &#9656; ▸
      &#x25B8; ▸
      &#9658; ►
      &#x25BA; ►
      &#9660; ▼
      &#x25BC; ▼
      &#9662; ▾
      &#x25BE; ▾
      &#9664; ◀
      &#x25C0; ◀
      &#9666; ◂
      &#x25C2; ◂
      &#9668; ◄
      &#x25C4; ◄
      &#x2122; ™
      &#x27; '
      &trade; ™
      &#00; -
      &#000; -
      &#33; !
      &#033; !
      &#34; {"}
      &#034; {"}
      &quot; {"}
      &#35; {#}
      &#035; {#}
      &#36; $
      &#036; $
      &#37; %
      &#037; %
      &#38; &
      &#038; &
      &amp; &
      &#39; '
      &#039; '
      &#40; (
      &#040; (
      &#41; )
      &#041; )
      &#42; *
      &#042; *
      &#43; +
      &#043; +
      &#44; ,
      &#044; ,
      &#45; -
      &#045; -
      &#46; .
      &#046; .
      &#47; /
      &#047; /
      &frasl; /
      &#48; -
      &#048; -
      &#58; :
      &#058; :
      &#59; ;
      &#059; ;
      &#60; <
      &#060; <
      &lt; <
      &#61; =
      &#061; =
      &#62; >
      &#062; >
      &gt; >
      &#63; ?
      &#063; ?
      &#64; @
      &#064; @
      &#65; -
      &#065; -
      &#91; [
      &#091; [
      &#92; \
      &#092; \
      &#93; ]
      &#093; ]
      &#94; ^
      &#094; ^
      &#95; _
      &#095; _
      &#96; `
      &#096; `
      &#97; -
      &#097; -
      &#123; {
      &#124; |
      &#125; }
      &#126; ~
      &#133; …
      &hellip; …
      &#150; –
      &ndash; –
      &#151; —
      &mdash; —
      &#152; -
      &#159; " "
      &#160; " "
      &#161; ¡
      &iexcl; ¡
      &#162; ¢
      &cent; ¢
      &#163; £
      &pound; £
      &#164; ¤
      &curren; ¤
      &#165; ¥
      &yen; ¥
      &#166; ¦
      &brvbar; ¦
      &brkbar; ¦
      &#167; §
      &sect; §
      &#168; ¨
      &uml; ¨
      &die; ¨
      &#169; ©
      &copy; ©
      &#170; ª
      &ordf; ª
      &#171; «
      &laquo; «
      &#172; ¬
      &not; ¬
      &#174; ®
      &reg; ®
      &#175; ¯
      &macr; ¯
      &hibar; ¯
      &#176; °
      &deg; °
      &#177; ±
      &plusmn; ±
      &#178; ²
      &sup2; ²
      &#179; ³
      &sup3; ³
      &#180; ´
      &acute; ´
      &#181; µ
      &micro; µ
      &#182; ¶
      &para; ¶
      &#183; ·
      &middot; ·
      &#184; ¸
      &cedil; ¸
      &#185; ¹
      &sup1; ¹
      &#186; º
      &ordm; º
      &#187; »
      &raquo; »
      &#188; ¼
      &frac14; ¼
      &#189; ½
      &frac12; ½
      &#190; ¾
      &frac34; ¾
      &#191; ¿
      &iquest; ¿
      &#192; À
      &Agrave; À
      &#193; Á
      &Aacute; Á
      &#194; Â
      &Acirc; Â
      &#195; Ã
      &Atilde; Ã
      &#196; Ä
      &Auml; Ä
      &#197; Å
      &Aring; Å
      &#198; Æ
      &AElig; Æ
      &#199; Ç
      &Ccedil; Ç
      &#200; È
      &Egrave; È
      &#201; É
      &Eacute; É
      &#202; Ê
      &Ecirc; Ê
      &#203; Ë
      &Euml; Ë
      &#204; Ì
      &Igrave; Ì
      &#205; Í
      &Iacute; Í
      &#206; Î
      &Icirc; Î
      &#207; Ï
      &Iuml; Ï
      &#208; Ð
      &ETH; Ð
      &#209; Ñ
      &Ntilde; Ñ
      &#210; Ò
      &Ograve; Ò
      &#211; Ó
      &Oacute; Ó
      &#212; Ô
      &Ocirc; Ô
      &#213; Õ
      &Otilde; Õ
      &#214; Ö
      &Ouml; Ö
      &#215; ×
      &times; ×
      &#216; Ø
      &Oslash; Ø
      &#217; Ù
      &Ugrave; Ù
      &#218; Ú
      &Uacute; Ú
      &#219; Û
      &Ucirc; Û
      &#220; Ü
      &Uuml; Ü
      &#221; Ý
      &Yacute; Ý
      &#222; Þ
      &THORN; Þ
      &#223; ß
      &szlig; ß
      &#224; à
      &agrave; à
      &#225; á
      &aacute; á
      &#226; â
      &acirc; â
      &#227; ã
      &atilde; ã
      &#228; ä
      &auml; ä
      &#229; å
      &aring; å
      &#230; æ
      &aelig; æ
      &#231; ç
      &ccedil; ç
      &#232; è
      &egrave; è
      &#233; é
      &eacute; é
      &#234; ê
      &ecirc; ê
      &#235; ë
      &euml; ë
      &#236; ì
      &igrave; ì
      &#237; í
      &iacute; í
      &#238; î
      &icirc; î
      &#239; ï
      &iuml; ï
      &#240; ð
      &eth; ð
      &#241; ñ
      &ntilde; ñ
      &#242; ò
      &ograve; ò
      &#243; ó
      &oacute; ó
      &#244; ô
      &ocirc; ô
      &#245; õ
      &otilde; õ
      &#246; ö
      &ouml; ö
      &#247; ÷
      &divide; ÷
      &#248; ø
      &oslash; ø
      &#249; ù
      &ugrave; ù
      &#250; ú
      &uacute; ú
      &#251; û
      &ucirc; û
      &#252; ü
      &uuml; ü
      &#253; ý
      &yacute; ý
      &#254; þ
      &thorn; þ
      &#255; ÿ
      &yuml; ÿ
      &Alpha; Α
      &alpha; α
      &Beta; Β
      &beta; β
      &Gamma; Γ
      &gamma; γ
      &Delta; Δ
      &delta; δ
      &Epsilon; Ε
      &epsilon; ε
      &Zeta; Ζ
      &zeta; ζ
      &Eta; Η
      &eta; η
      &Theta; Θ
      &theta; θ
      &Iota; Ι
      &iota; ι
      &Kappa; Κ
      &kappa; κ
      &Lambda; Λ
      &lambda; λ
      &Mu; Μ
      &mu; μ
      &Nu; Ν
      &nu; ν
      &Xi; Ξ
      &xi; ξ
      &Omicron; Ο
      &omicron; ο
      &Pi; Π
      &pi; π
      &Rho; Ρ
      &rho; ρ
      &Sigma; Σ
      &sigma; σ
      &Tau; Τ
      &tau; τ
      &Upsilon; Υ
      &upsilon; υ
      &Phi; Φ
      &phi; φ
      &Chi; Χ
      &chi; χ
      &Psi; Ψ
      &psi; ψ
      &Omega; Ω
      &omega; ω
      &#9679; ●
      &#8226; •
      &#8734; ∞
      &infin; ∞
    }
    set title [string map $html_mapping $text]
    return $title
  }

  putlog "Initialized Url Title Grabber v$scriptVersion"
}
