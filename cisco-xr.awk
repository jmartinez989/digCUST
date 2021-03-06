#!/bin/awk -f

##########################################################################################
# Start of BEGIN block
BEGIN {

    ##########################################################################################
    # Array Declrarations
    #
    # The reason that the array index 0 for each array is assigned and then
    # deleted is because there is no way to declare a variable as an array
    # in awk for later use. The only way to do it is to declar the array with an
    # index and then delete the index entry. You can then reuse the variable as an
    # array. If you try to delcare the array as "arr = ''" and then later try to
    # use it as an array such as "arr[0] = 1" then awk will throw an error stating
    # that you are trying to use a scalar as an array.
    ##########################################################################################

    #This array will be used for storing QoS values of bridge domains.
    bdArr[0]
    delete bdArr[0]

    #This array will be used for storing information on interfaces such as ip address and vrf tag.
    interfaces[0]
    delete interfaces[0]

    #This array will be used to store all interfaces associated with a vrf tag. The indicies to the array will
    #be a vrf tag and the value will be a comma sparated list of all interfaces ited to that vrf.
    vrfTags[0]
    delete vrfTags[0]

    #This will hold the hostname of the device who's config is being processed.
    hostname = ""
}
# End of BEGIN block
##########################################################################################

#This case grabs the hostname of the device from the line containing the hostname.
/^hostname/ {
    hostname = tolower($2)
    filenamesplit = split(FILENAME, splitnames, "/")

    if(hostname != splitnames[filenamesplit]) {
        hostname = hostname " aka " splitnames[filenamesplit]
    }
}

#In this case the scraper will be processing the description of an interface.
/^interface [^ ]+ ([^ ]+ )?description/ {
    intName = $2
    accountNum = gensub(/.*%([0-9A-Za-z]+)%.*/, "\\1", "g", $0)
    gsub(/ /, "", accountNum)

    #If the variable accountNum still contains the word description then the substitution failed so try looking
    #for the account number between "|" pipe characters.
    if(accountNum ~ "description") {
        accountNum = gensub(/.*\|([0-9A-Za-z]+)\|.*/, "\\1", "g", $0)
        
        #The breadkdown of this statement is if the variable account number contains the string "description"
        #then that means that the substitution failed and so the variable will just contain the record text. If
        #that is the case then the account number is set to "N/A".
        interfaces[intName".accountNum"] = (accountNum !~ "description") ? accountNum : "N/A"
    } else {
         interfaces[intName".accountNum"] = accountNum
    }

    interfaces[intName".description"] = gensub(/.*description (.*)/, "\\1", "g")
}

#This section will extract the vrf of an interface off of the current record.
/^interface [^ ]+ ([^ ]+ )?vrf/ {
    intName = $2
    vrfTag = ""

    if($3 == "vrf") {
        vrfTag = $4
    } else {
        vrfTag = $5
    }
    
    interfaces[intName".vrf"] = vrfTag

    #After getting the vrf tag assigned to the interface store the tag of that interface to the vrfTags array.
    vrfTags[vrfTag] = vrfTags[vrfTag] "," intName
    vrfTags[vrfTag] = removeTrailingAndLeadingCommas(vrfTags[vrfTag])
}

#This section will extract the ip address of an interface off of the current record.
/^interface [^ ]+ ([^ ]+ )?ipv4 address [0-9]/ {
    intName = $2
    intIp = ""
    intMask = ""
    wan = ""
    wanIpCIDR = ""

    #This section of code assigns a QoS value to DLCI interfaces of a multilink frame relay interface. Since the
    #QoS configuration is on the MFR parent interface, the DLCI interfaces will not contain the QoS config so in
    #order to assing them the QoS value look at just the name of the interface without the "." and see if that has
    #QoS and if it does then assign it to the DLCI interfaces.
    if(intName ~ /Multilink[0-9]\/[0-9]\/[0-9]\/[0-9]\/[0-9]+\./) {
        mfrName = gensub(/(Multilink[0-9]\/[0-9]\/[0-9]\/[0-9]\/[0-9]+).*/, "\\1", "g", intName)
        if(interfaces[mfrName".QoS"] != 0) {
            interfaces[intName".QoS"] = interfaces[mfrName".QoS"]
        } else {
            #This array entry needs to be deleted because the reference to it above sets it
            #to a blank value even though it was not set prevously.
            delete interfaces[mfrName".QoS"]
        }
    } else if(intName ~ /Serial.*\./) {
        frSerial = gensub(/(Serial.*)\.[0-9]+/, "\\1", "g", intName)

        if(interfaces[frSerial".QoS"] != 0) {
            interfaces[intName".QoS"] = interfaces[frSerial".QoS"]
        } else {
            #This array entry needs to be deleted because the reference to it above sets it
            #to a blank value even though it was not set prevously.
            delete interfaces[frSerial".QoS"]
        }
    }

    #The ip address may sometimes be the 5th field in the record and may sometimes be the 6th so this check has to be perfomed.
    #The netmask is stored along with the ip address.
    if($4 == "address") {
        intIp = $5
        intMask = $6
    } else {
        intIp = $6
        intMask = $7
    }
    
    network = ipToDecimal(getNetworkIp(intIp, intMask))
    broadcast = ipToDecimal(getBroadcastIp(intIp, intMask))
    wan = getNetworkIp(intIp, intMask) "/" getCIDRMask(intMask) "%" network "_" broadcast "%"
    wanIpCIDR = intIp "/" getCIDRMask(intMask)

    interfaces[intName".wanIpCIDR"] = wanIpCIDR

    if(interfaces[intName".wan"] == "") {
        #This is where the wan, network and broadcast are stored for the interface. The network and broadcast are stored as
        #decimal numbers because those will be used later on to compare the next hop ip of a static route to see if it falls
        #between the range of network and broadcast of this interface. If it does then the route belongs to that interface.
        interfaces[intName".wan"] = wan

        #The record that processes the interface vrf is processed before the interface's ip address so the vrf tag will be
        #processed at this point. If the interface did not have a vrf tag then index 'intName".vrf"' will be blank meaning
        #that the interface has no vrf so place it in the slot for vrf tag "none".
        if(interfaces[intName".vrf"] == "") {
            vrfTags["none"] = vrfTags["none"] "," intName
            vrfTags["none"] = removeTrailingAndLeadingCommas(vrfTags["none"])
        }
    #This case will be for when the wan has already been assigned. If it has check to see if the currently processed wan is
    #already a part of the interface's wan. If it is not then append this wan to the end of the interface's wan list.
    } else {
        if(interfaces[intName".wan"] !~ wan) {
            interfaces[intName".wan"] = removeTrailingAndLeadingCommas(interfaces[intName".wan"] "," wan)
        }
    }
}

#This section will extract the QoS policy out of an interface that has one directly applied to it.
/^interface [^ ]+ ([^ ]+ )?service-policy output / {
    intName = $2
    interfaces[intName".QoS"] = $NF
}

#S. Pierce - Added support for storing 802.1q VLAN tags July 2nd 2018
/^interface [^ ]+ ([^ ]+ )?encapsulation dot1q / {
    intName = $2
    vlanTags = ""
    if($4 ~ /dot1q/ &&  $6 ~ /second-dot1q/) {
        vlanTags = $5 "%" $7
    } else {
         vlanTags = $5
    }
    interfaces[intName".vlanTags"] = vlanTags
}


#The ip routes will be assigned to their interfaces in this section.
# Sample entry: router static address-family ipv4 unicast 40.138.27.144/29 40.138.26.61
/^router static (vrf|address)/ {
    #The next hop of the route. This will either be an interface name or an ip address.
    nextHop = ""
    #This will be used if the first case of next hop is an interface. If it is then check the field after it and see if that is
    #an ip address. If it is then that is the ip next hop which will be the ip address of the CPE it is being routed to.
    nextHop2 = ""
    #This will hold the vrf tag for any vrf routes.
    vrfLabel = ($3 == "vrf") ? $3 : ""
    #This will hold the actual route to be assigned out.
    lanNetwork = ""
    #This will hold the interface name where the route is routed to.
    intName = ""
    #This will hold the network ip of the ip address of the interface.
    networkIp = ""
    #This will hold the broadcast ip of the ip address of the interface.
    broadcastIp = ""
    #If a next hop for the route is an ip then this will hold the decimal value of that ip.
    nextHopDecimal = ""
    #This array will hold the list of all the interfaces that are part of the vrf.
    vrfInterfaces[0]
    delete vrfInterfaces[0]
    #This will hold the number of interfaces in the given vrf tag associated with the route. If the route is a non vrf route then
    #this number will be the number of interfaces with the vrf tag "none".
    numInterfaces = 0
    #This array will hold the number of wan ips that an interface might have (some have more than 1).
    wanArr[0]
    delete wanArr[0]
    #iteration over the WAN ips of an interface will occur and when this does the network and broadcast numbers will be stored
    #in this array. The network ip will be the first element and the boradcast will be the second element.
    networkBraodcastSplit[0]
    delete networkBraodcastSplit[0]
    #This will store the number of WAN ips on an interface when splitting them up.
    numWans = 0
    #This will hold the string in between "()" part of the WAN ip string. The WAN ips at this point will be in the format of
    #"X.X.X.X/XX([networknumber]_[broadcastnumber])".
    networkBroadcastString = ""

    if(vrfLabel != "") {
        lanNetwork = $8
        nextHop = $9
        nextHop2 = $10
    } else {
        lanNetwork = $6
        nextHop = $7
        nextHop2 = $8
    }

    #If next hop is an interface then assign the route to the interface.
    if(nextHop ~ /[A-Za-z]/) {
        intName = nextHop
        interfaces[intName".lan"] = interfaces[intName".lan"] "," lanNetwork
        interfaces[intName".lan"] = removeTrailingAndLeadingCommas(interfaces[intName".lan"])

        #This statement assigns the CPE ip the value of nextHop2 if nextHop2 is an ipa ddress or "N/A" otherwise.
        interfaces[intName".cpeIp"] = (nextHop2 ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) ? nextHop2 : "N/A"

    #Next hop is an ipaddress, start looking for the interface with said IP address.
    } else {
        if(vrfLabel != "") {
            numInterfaces = split(vrfTags[vrfLabel], vrfInterfaces, ",")
        } else {
            numInterfaces = split(vrfTags["none"], vrfInterfaces, ",")
        }

        nextHopDecimal = ipToDecimal(nextHop)

        for(k = 1; k <= numInterfaces; k++) {
            intName = vrfInterfaces[k]

            #It is possible to get an interface without a wan ip so skip the entry if it does not.
            if(interfaces[intName".wan"] != "") {
                numWans = split(interfaces[intName".wan"], wanArr, ",")

                for(i = 1; i <= numWans; i++) {
                    networkBroadcastString = gensub(/.*%([^%]+)%/, "\\1", "g", wanArr[i])
                    split(networkBroadcastString, networkBraodcastSplit, "_")
                    networkIp = networkBraodcastSplit[1]
                    broadcastIp = networkBraodcastSplit[2]

                    #If the nexthop is between the network ip and the broadcast ip then this route must belong to the interface.
                    if((nextHopDecimal >= networkIp) && (nextHopDecimal <= broadcastIp)) {
                        interfaces[intName".cpeIp"] = nexthop
                        interfaces[intName".lan"] = interfaces[intName".lan"] "," lanNetwork
                        interfaces[intName".lan"] = removeTrailingAndLeadingCommas(interfaces[intName".lan"])
                        # Since the interface for the route was found we can just move on to the next input record.
                        next
                    }
                }
            }
        }
    }
}

#This section will catch to see if an interface is shutdown and will mark the status of the interface accordingly.
/^interface [^ ]+ ([^ ]+ )?shutdown/ {
    intName = $2
    interfaces[intName".status"] = "Administrative Down"
}


#This section will be used to populate the array serviceGroups with the QoS policies for service groups.
/^l2vpn bridge group [^ ]+ bridge-domain [^ ]+ interface/ {
    intName = $8
    bridgeDomain = $6

    if(interfaces[intName".QoS"] != "") {
        intQOS = interfaces[intName".QoS"] " (" intName ")"
        bdArr[bridgeDomain] = removeTrailingAndLeadingCommas(bdArr[bridgeDomain] "," intQOS)
    }

    delete interfaces[intName".QoS"]
}

#This section will be used to assign BVI interfaces with the QoS values amassed in the bridge-domain.
/^l2vpn bridge group [^ ]+ bridge-domain [^ ]+ routed interface/ {
    intName = $NF
    bridgeDomain = $6
    interfaces[intName".QoS"] = bdArr[bridgeDomain]
}

##########################################################################################
# Start of getCIDRMask() function
#
# This function will be used to get the CIDR mask notation of the subnet mask of an interface. What
# it does is turns the ip format of the net mask into a decimal and then takes a bit mask that starts
# at 2^31 (only left most bit is on) and then does a bitwise AND on the netmask and if the value is
# greater than zero then it counts 1 bit on for the netmask. It then decrements the the exponent by
# 1 and does this again until the exponent is less than 0. The number of bits counted as on will be
# returned as the CIDR notation mask.
#
# Parameters:
#     mask: The subnet mask of the ipaddress in ip notation.
#
# Local Variables:
#     cidrmask: This variable will be used to hold the value of the calculated CIDR mask and will be the
#     return value for this function.
#
#     maskDecimal: The subnet mask in decimal format.
#
#     maskBitExponent: This will be used to dtermine what the bitmask will be to apply to the netmask
#                      to determin how many bits in the netmask are on which will indicate the CIDR
#                      mask. It sarts with value of 31 (left most bit on when doing 2^31) and then
#                      goes down by 1 until it gets below 0.
#
#     bitsOn: The number of bits in the netmask that are on to indicat CIDR mask.
#
#     bitMask: The bitMask that applies to the netmask to count if a bit is on. It starts with the left most
#              bit of a 32 bit integer as 1 (2^31). The exponent for the calcuation of the bitmask is decreased
#              by 1 until the exponent is below zero. This simulates a right shift of the on bit of the mask.
function getCIDRMask(mask,    maskDeciaml, maskBitExponent, bitsOn, bitMask) {
    maskDeciaml = ipToDecimal(mask)
    maskBitExponent = 31
    bitsOn = 0
    bitMask = 0

    while(maskBitExponent >= 0) {
        bitMask = 2 ** maskBitExponent

        if(and(maskDeciaml, bitMask) > 0) {
            bitsOn++
        }

        maskBitExponent--
    }

    return bitsOn
}
# End of getCIDRMask() function
##########################################################################################

##########################################################################################
# Start of getNetworkIp() function
#
# This function will be used to get the netwok ip of the ip address of an interface. What it will do
# is take an ip address and subnet mask, convert them both to decimal format, do a bitwise AND of both
# values and then covert that value back to ip address format which will be the network ip.
#
# Parameters:
#     ipaddress: The ip address of the interface (could also be used for any ip address, this function
#     will mainly be used to get the network ip of interfaces though).
#
#     mask: The subnet mask of the ipaddress in ip notation.
#
# Local Variables:
#     networkip: This variable will be used to hold the value of the calculated network ip address and will be the
#     return value for this function.
#
#     maskDecimal: The decimal representation of the net mask.
#
#     ipDecimal: The decimal representation of the ip address.
function getNetworkIp(ipaddress, mask,    networkip, maskDecimal, ipDecimal) {
    maskDecimal = ipToDecimal(mask)
    ipDecimal = ipToDecimal(ipaddress)
    networkip = decimalToIP(and(ipDecimal, maskDecimal))

    return networkip
}
# End of getNetworkIp() function
##########################################################################################

##########################################################################################
# Start of getBroadcastIp() function
#
# This function will be used to get the broadcast ip of the ip address of an interface. What it will do
# is take an ip address and subnet mask, convert them both to decimal format, then it will take the
# value of the mask and convert it to its complement and then the complement mask and the decimal ip
# have a bitwise OR operation done on them and then the result is turned back into ip address notation
# which will be the brodcast ip.
#
# Parameters:
#     ipaddress: The ip address of the interface (could also be used for any ip address, this function
#     will mainly be used to get the broadcast ip of interfaces though).
#
#     mask: The subnet mask of the ipaddress in ip notation.
#
# Local Variables:
#     broadcastip: This variable will be used to hold the value of the calculated broadcast ip address and will be the
#     return value for this function.
#
#     command: This variable will be used to store the ipcalc command as a string so that it can be piped to 
#     getline and will then be stored in broadcastip.
function getBroadcastIp(ipaddress, mask,    octet1, octet2, octet3, octet4, bitMask, maskCompliment) {
    maskDecimal = ipToDecimal(mask)
    maskCompliment = compl(maskDecimal)
    ipDecimal = ipToDecimal(ipaddress)
    networkip = decimalToIP(or(ipDecimal, maskCompliment))

    return networkip
}
# End of getBroadcastIp() function
##########################################################################################

##########################################################################################
# Start of ipToDecimal() function
#
# This function will be used to take an ip address and turn it into a decimal number. This will be usefull in determining
# if an ip address falls witin a range of ips (like if an ip falls between a network ip and a broadcast ip). The formula for
# this is the one below:
#     (first octet * 256^3) + (second octet * 256^2) + (third octet * 256) + (fourth octet)
#
# Parameters:
#     ipaddress: The ip address that will be converted to a decimal number.
#
# Local Variables:
#     octets: An array that will store each octet of the ip address passed in. This array will always have 4 indicies
#     as an ip address will always have 4 values.
#
#     decimalVal: This variable will hold the calculated decimal number of the ip address in quesiton. This will be the function's
#     return value.
#
#     power: This variable is used to raise 255 to the needed power as per the formula above so that calculation can be performed
#     correctly.
function ipToDecimal(ipaddress,    octets, decimalVal, power) {
    split(ipaddress, octets, ".")
    decimalVal = 0
    power = 3

    for(i = 1; i <= 4; i++) {
        decimalVal += (octets[i] * (256 ** power))
        --power
    }

    return decimalVal
}
# End of ipToDecimal() function
##########################################################################################

##########################################################################################
# Start of decimalToIP() function
#
# The purpose of this function is to take a decimal value and turn it into an ip address.
# The way this is done is to take a bit mask with 32 bits and turn all 8 left most bits
# on. When thi sis done do a bitwise AND of the decimal number and the bit mask. After that
# shift the bits in the bit mask by 8 bits and do this process again until 4 bits have been
# acquired.
#
# Parameters:
#     decimalIp: Decimal number representing the ip address.
#
# Local Variables:
#     octetN: SShortend for N being values 1-4. These will be the values that will make up
#             the ip address.
#
#     bitMask: The mask to use to determin each octet.
function decimalToIP(decimalIp,     octet1, octet2, octet3, octet4, bitMask) {
    # 8 left most bits set to on (11111111000000000000000000000000), will get shifted right
    # for other octets.
    bitMask = 4278190080

    # Bitwise AND of mask and decimal value has to be right shifted to get the correct value
    # of between 0 and 255 because if that is not done then you will get an invalid value for
    # an octet. So for the first octet you have to shift by 24 bits to the right, the second
    # octet shift by 16, the third by 8 and since the last octet will be the right most 8
    # bits of the decimal IP there is no need to shift.
    octet1 = rshift(and(decimalIp, bitMask), 24)
    bitMask = rshift(bitMask, 8)
    octet2 = rshift(and(decimalIp, bitMask), 16)
    bitMask = rshift(bitMask, 8)
    octet3 = rshift(and(decimalIp, bitMask), 8)
    bitMask = rshift(bitMask, 8)
    octet4 = and(decimalIp, bitMask)

    return octet1"."octet2"."octet3"."octet4
}
# End of ipToDecimal() function
##########################################################################################

##########################################################################################
# Start of removeTrailingAndLeadingCommas() function
#
# This function will simply just remove any trailing or leading commas from a string. Made this a function because it was 
# something that was being done quite a few times in other parts of this script.
#
# Parameters:
#     commaString: The string to be stripped of commas.
#
#     formattedString: This will be the resulting string that will be free of commas. This will be this function's return value.
function removeTrailingAndLeadingCommas(commaString,    formattedString) {
    formattedString = gensub(/(^,+|,+$)/, "", "g", commaString)

    return formattedString
}
# End of removeTrailingAndLeadingCommas() function
##########################################################################################

##########################################################################################
# Start of printDBFile() function
#
# This function will simply print out the content of all interface information to digCUST database file.
#
# No Parameters or return values.
function printDBFile() {
    for(vrfTag in vrfTags) {
        numInterfaces = split(vrfTags[vrfTag], vrfInterfaces, ",")

        for(i = 1; i <= numInterfaces; i++) {
            interfaceName = vrfInterfaces[i]

            #Only print this interface to file if it even has an IP address. There may be some interfaces without an IP
            #that get thrown into the interfaces array that also have VRF tags.
            if(interfaces[interfaceName".wan"] != "") {
                #Need to remove the "(.*)" section of the WAN ip before output since it is not desired to output it.
                gsub(/%[^%]+%/, "", interfaces[interfaceName".wan"])

                #At this point there is still a possiblity that some fields that will be displayed will not hava a value. If that
                #is the case then set the fields to the value of "N/A".
                if(interfaces[interfaceName".cpeIp"] == "") {
                    interfaces[interfaceName".cpeIp"] = "N/A"
                }

                if(interfaces[interfaceName".QoS"] == "") {
                    interfaces[interfaceName".QoS"] = "N/A"
                }

                if(interfaces[interfaceName".vlanTags"] == "") {
                    interfaces[interfaceName".vlanTags"] = "N/A"
                }

                if(interfaces[interfaceName".status"] == "") {
                    interfaces[interfaceName".status"] = "no shutdown"
                }

                if(interfaces[interfaceName".accountNum"] == "") {
                    interfaces[interfaceName".accountNum"] = "N/A"
                }

                if(interfaces[interfaceName".vrf"] == "") {
                    interfaces[interfaceName".vrf"] = "N/A"
                }

                if(interfaces[interfaceName".lan"] == "") {
                    interfaces[interfaceName".lan"] = "N/A"
                }
                #This section formats the information of an interface and appends it all to a string. There are several fields
                #in this string such as account number or interface QoS or vrf tag. Once the string is formatted it is printed
                #to the database file.
                intRecord = "\"" hostname "\""
                intRecord = intRecord ":::\"" interfaceName "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".accountNum"]  "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".description"] "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".vrf"] "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".wan"] "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".lan"] "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".QoS"] "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".status"] "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".wanIpCIDR"] "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".cpeIp"] "\""
                intRecord = intRecord ":::\"" interfaces[interfaceName".vlanTags"] "\""

                #digCustFile will be an argument passed into the script via -v digCustFile=*filename*
                print intRecord >> digCustFile
            }
        }
    }

    close(digCustFile)
}

# End of printDBFile() function
##########################################################################################

END {
    #If hostname is blank that means there was no hostname which means this is not a valid config file so the entire END procedure 
    #will not execute.
    if(hostname != "") {
        printDBFile()
    }
}