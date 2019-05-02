#!/bin/gawk -f

#############################################################################
# BEGIN PROCEDURE
# Setting up all constants and globals
BEGIN {
    ########################
    # CONSTANTS
    ########################

    #Indentation formatter for output
    INDENT = "    "

    #Setting up color escape character modifiers
    CYAN = "\033[36m"
    GREEN = "\033[32m"
    RED = "\033[31m"
    YELLOW = "\033[33m"

    #Setting up text format escape character modifiers
    
    #Bold Midofier
    B = "\033[1m"

    #Italics Modifier
    I = "\033[3m"

    #Underline Modifier
    U = "\033[4m"

    #Setting up modifier terminator
    TERM = "\033[0m"

    HTMLU = "<u>"
    HTMLENDU = "</u>"
    HTMLB = "<b>"
    HTMLENDB = "</b>"
    HTMLFONTRED = "<font color=\"#FF0000\">"
    HTMLFONTCYAN = "<font color=\"#00a2cc\">"
    HTMLFONTYELLOW = "<font color=\"#b2b300\">"
    HTMLENDFONT = "</font>"

    #The max number of output lines per customer record.
    NUMLINES = 6

    if(web) {
        noascii = 0
    }
}
# END BEGIN PROCEDURE
#############################################################################





#############################################################################
# MAIN INPUT LOOP
#
{
    #Set up all properties of currenty entry. Names self decribe the property except for status.
    #status is either going to be blank or be "Admin Down" indicating that the interface is shutdown
    device = $1
    interface = $2
    account = $3
    description = $4
    vrf = $5
    wan = $6
    lan = $7
    qos = $8
    status = $9

    #S. Pierce - Adding new fields July 9, 2018
    intip = $10
    cpe = $11
    vlans = $12

    #Array for printing output lines. Just setting first index to blank to initalize.
    lines[1] = ""

    #S. Pierce - Array for vlan tags when more than one is used. Set just to initialize.
    dot1q[1] = ""

    #This list of gsub() calls are to replace the " characters from all fields.
    gsub("\"", "", vrf)
    gsub("\"", "", status)
    gsub("\"", "", description)
    gsub("\"", "", device)
    gsub("\"", "", account)
    gsub("\"", "", wan)
    gsub("\"", "", qos)
    gsub("\"", "", interface)
    gsub("\"", "", lan)
    gsub("\"", "", intip)
    gsub("\"", "", cpe)
    gsub("\"", "", vlans)

    if(csv) {
        gsub(/,/, ";", lan)
        gsub(/,/, "", description)

        if(status == "no shutdown") {
            status = "Admin Up"
        }
               
        print device "," interface "," account "," description "," vrf "," wan "," lan "," qos "," status "," intip "," cpe "," vlans
    } else if(json) {
        jsonstring = "{\n"
        jsonstring = jsonstring "    \"device\": " device ",\n"
        jsonstring = jsonstring "    \"interface\": " interface ",\n"
        jsonstring = jsonstring "    \"account\": " account ",\n"
        jsonstring = jsonstring "    \"description\": " description ",\n"
        jsonstring = jsonstring "    \"vrf\": " vrf ",\n"
        jsonstring = jsonstring "    \"wan\": " wan ",\n"
        jsonstring = jsonstring "    \"lan\": " lan ",\n"
        jsonstring = jsonstring "    \"qos\": " qos ",\n"
        jsonstring = jsonstring "    \"status\": " status ",\n"
        jsonstring = jsonstring "}"

        print jsonstring
    } else {
        lines[3] = INDENT "Interface: " interface

        if(noascii) {
            formatNoAscii(lines)
        } else if(web) {
            formatWeb(lines)
        } else {
            formatAscii(lines)
        }
        
        #S. Pierce - July 9, 2018 - Added output for next-hop (cpe) and interface IP 
        if(cpe != "N/A") {
            lines[5] = INDENT "WAN: " wan " (IP: " intip ", Next-hop: " cpe ")"
        } else {
            lines[5] = INDENT "WAN: " wan " (IP: " intip ")"
        }

        lines[6] = (length(lan) > 0) ? INDENT "LAN: " lan : ""

        for (i = 0; i <= NUMLINES; i++) {
            if(length(lines[i]) > 0) {
                print lines[i]
            }
        }

        print ""
    }
}
# END MAIN INPUT LOOP
#############################################################################

function formatAscii(linesArr) {
    linesArr[1] = U description TERM " %" CYAN account TERM "%"
    linesArr[2] = INDENT B device TERM

    if(vrf != "N/A") {
        linesArr[3] = linesArr[3] " (" CYAN vrf TERM ")"
    }

    #S. Pierce -  July 9, 2018 - Added new VRF fields
    if(vlans != "N/A") {

        if (vlans ~ /%/) {
            split(vlans, dot1q, "%")
            linesArr[3] = linesArr[3] " <" YELLOW "SVLAN: " dot1q[1] " CVLAN: " dot1q[2] TERM ">"
        } else {
            linesArr[3] = linesArr[3] " <" YELLOW "SVLAN: " vlans TERM ">"
        }
    }

    if(status != "no shutdown") {
        linesArr[3] = linesArr[3] " [" RED status TERM "]"
    }

    lines[4] = INDENT "QoS Policy: " YELLOW qos TERM
}

function formatNoAscii(linesArr) {
    linesArr[1] = description " %" account "%"
    linesArr[2] = INDENT device

    if(vrf != "N/A") {
        linesArr[3] = linesArr[3] " (" vrf ")"
    }


    #S. Pierce -  July 9, 2018 - Added new VRF fields
    if(vlans != "N/A") {

        if (vlans ~ /%/) {
            split(vlans, dot1q, "%")

            linesArr[3] = linesArr[3] " <SVLAN: " dot1q[1] " CVLAN: " dot1q[2] ">"
        } else {
            linesArr[3] = linesArr[3] " <SVLAN: " vlans ">"
        }
    }

    if(status != "no shutdown") {
        linesArr[3] = linesArr[3] " [" status "]"
    }

    lines[4] = INDENT "QoS Policy: " qos
}

function formatWeb(linesArr) {
    linesArr[1] = HTMLU description HTMLENDU " %" HTMLFONTCYAN account HTMLENDFONT "%"
    linesArr[2] = INDENT HTMLB device HTMLENDB

    if(vrf != "N/A") {
        linesArr[3] = linesArr[3] "(" HTMLFONTCYAN vrf HTMLENDFONT ")"
    }

    #S. Pierce -  July 9, 2018 - Added new VRF fields
    if(vlans != "N/A") {

        if (vlans ~ /%/) {
            split(vlans, dot1q, "%")

            linesArr[3] = linesArr[3] " <" HTMLFONTYELLOW " SVLAN: " dot1q[1] " CVLAN: " dot1q[2] HTMLENDFONT ">"
        } else {
            linesArr[3] = linesArr[3] " <" HTMLFONTYELLOW " SVLAN: " vlans HTMLENDFONT ">"
        }
    }

    if(status != "no shutdown") {
        linesArr[3] = linesArr[3] " [" HTMLFONTRED status HTMLENDFONT "]"
    }

    lines[4] = INDENT "QoS Policy: " HTMLFONTYELLOW qos HTMLENDFONT
}