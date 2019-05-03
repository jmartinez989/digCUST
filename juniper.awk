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

    #This array will be used for storing information on interfaces such as ip address and vrf tag.
    interfaces[0]
    delete interfaces[0]

    #This array will be used for storing QoS values of bridge domains.
    bdArr[0]
    delete bdArr[0]

    #This array will hold interface names at an index that is the decimal number representation of the ip address
    #of the interface. More specfically it will store the same interface name in the range of ips starting at the
    #network ip of the interface up to the broadcast ip. For interfaces with vrf tags the index value will be
    #prepended to the index number of the entry.
    interfaceIps[0]
    delete interfaceIps[0]

    #This array will be used to store all interfaces associated with a vrf tag. The indicies to the array will
    #be a vrf tag and the value will be a comma sparated list of all interfaces ited to that vrf.
    vrfTags[0]
    delete vrfTags[0]

    #This array will be used to hold the interfaces that are part of an interface set so that the QoS policies
    #applied to those interface sets can be applied to the individual interfaces.
    interfaceSets[0]
    delete interfaceSets[0]

    #This will hold the hostname of the device who's config is being processed.
    hostname = ""
}
# End of BEGIN block
##########################################################################################

#This section will take the vrfTags and assign them to interfaces. In order to do this an external call to grep on the
#current file is made so that interfaces can have their vrfs assigned to them before anything else. The reason this is done
#is because the vrf for an interface will need to exist before certain other elements are processed.
NR == 1 {
    command = "egrep \"^routing-instances [^ ]+ interface\" " FILENAME
    
    #In this case each line of the pipe is stored into $0 because there is no variable used to stoe the line read in so we can
    #treat the lines read in as normal input records to this script.
    while((command | getline) > 0) {
        vrfLabel = $2
        vrfInterface = $4
        vrfTags[vrfLabel] = removeTrailingAndLeadingCommas(vrfTags[vrfLabel] "," vrfInterface)
        interfaces[vrfInterface".vrf"] = vrfLabel
    }

    close(command)
}

#This case grabs the hostname of the device.
/system host-name/ {
    #Junipers can have multiple lines that contain the host name so have to check if the hostname has already been
    #set.
    if(hostname == "") {
        #Junipers have 2 different sets of configs that store the hostname for the device. The first one takes on the format:
        #    groups re[0-9]+ system host-name devicename-re[0-9]+
        #The system name can also be in the format of:
        #    system host-name devicename
        #In the first case the device name is the last field in the input record with the suffix "re[0-9]+" appended to it. In
        #that case the suffix has to be stripped and that leaves the host name to assign. In the second case the device name
        #is simply just the third field in the input record.
        if(NF > 3) {
            hostname = gensub(/(.*)-[rR][eE][0-9]+/, "\\1", "g", $5)
        } else {
            hostname = $3
        }

        hostname = tolower(hostname)
        filenamesplit = split(FILENAME, splitnames, "/")

        if(hostname != splitnames[filenamesplit]) {
            hostname = hostname " aka " splitnames[filenamesplit]
        }
    }
}

#This section will catch to see if an interface is shutdown and will mark the status of the interface accordingly.
/^interfaces inactive/ {
    intName = ""

    if($4 == "unit") {
        intName = $3 "." $5
    } else {
        intName = $3
    }

    interfaces[intName".status"] = "Inactive"
}

#This section will grab the status of a disabled interface and mark the interface as such.
/interfaces [^ ]+ (disable|unit [0-9]+ disable)/ {
    intName = ""

    if($3 == "disable") {
        intName = $2
    } else {
        intName = $2 "." $4
    }

    interfaces[intName".status"] = "Disabled"
}

#This section will grab interfaces that are part of interface sets and store them in the interfaceSets array.
/interfaces interface-set/ {
    setName = ""
    intName = ""

    if($3 != "interface") {
        setName = $3

        if($6 == "unit") {
            intName = $5 "." $7           
        } else {
            intName = $5
        }

        interfaceSets[setName] = removeTrailingAndLeadingCommas(interfaceSets[setName] "," intName)
    }
}

#This section will grab the IP address off of an interface.
/^interfaces (inactive: )?[^ ]+ (unit [0-9]+ )?family inet address/ {
    #This will hold the ip address of the interface.
    ip = gensub(/.* ([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\/[0-9]+.*/, "\\1", "g")
    #This will hold the subnet mask of the ip address.
    mask = gensub(/.* [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(\/[0-9]+).*/, "\\1", "g")
    #This will hold the name of the interface being processed.
    intName = ""
    #This will hold the network ip address of the WAN for the interface being processed in this record.
    wan = ""
    #This variable will only ever be set if the interface in this record is a "unit (subinterface)" and if it has
    #no description available.
    parentInterface = ""

    network = ""

    broadcast = ""

    wanIpCIDR = ""

    if($2 == "inactive:") {
        if($4 == "unit") {
            intName = $3 "." $5
        } else {
            intName = $3
        }
    } else {
        if($3 == "unit") {
            intName = $2 "." $4
        } else {
            intName = $2
        }
    }

    #Check to see if the interface has a description.
    if(interfaces[intName".description"] == "") {
        #Now check to see if the record has the word "unit" in it.
        if($0 ~ /unit/) {
            #Have to check to see if this record contains the word "inactive". If it does then the parent interface will
            #be the 3rd field in the record, otherwise it will be the second.
            if($2 ~ /inactive/) {
                parentInterface = $3
            } else {
                parentInterface = $2
            }

            interfaces[intName".description"] = interfaces[parentInterface".description"]
        }
    }

    network = ipToDecimal(getNetworkIp(ip, mask))
    broadcast = ipToDecimal(getBroadcastIp(ip, mask))
    wan = getNetworkIp(ip, mask) mask "%" network "_" broadcast "%"
    wanIpCIDR = ip mask
    interfaces[intName".wanIpCIDR"] = wanIpCIDR

    #If this interface's wan ip has not been processed yet then assign it as needed.
    if(interfaces[intName".wan"] == "") {
        interfaces[intName".wan"] = wan

        #The record that processes the interface vrf is processed before the interface's ip address so the vrf tag will be
        #processed at this point. If the interface did not have a vrf tag then index 'intName".vrf"' will be blank meaning
        #that the interface has no vrf so place it in the slot for vrf tag "none".
        if(interfaces[intName".vrf"] == "") {
            vrfTags["none"] = removeTrailingAndLeadingCommas(vrfTags["none"] "," intName)
        }
    #This case will be for when the wan has already been assigned. If it has check to see if the currently processed wan is
    #already a part of the interface's wan. If it is not then append this wan to the end of the interface's wan list.
    } else {
        if(interfaces[intName".wan"] !~ wan) {
            interfaces[intName".wan"] = removeTrailingAndLeadingCommas(interfaces[intName".wan"] "," wan)
        }
    }
}

#In this case the scraper will be processing the description and account number of an interface.
/^interfaces (inactive: )?[^ ]+ (unit [0-9]+ )?description/ {
    intName = ""
    accountNum = ""

    #If the second field in this record is "inactive" then this is not an interface.
    if($2 != "inactive:") {
        #If the third field in the record is the word "unit" then this interface is a subinterface to a main transpport
        #interface. If that is the case then place a "." and then the unit number at the end of an interface name to
        #denote it as a separate interface (example interface xe-2/1/0 unit 10 will be xe-2/1/0.10).
        if($3 == "unit") {
            intName = $2 "." $4
        } else {
            intName = $2    
        }
    } else {
        if($4 == "unit") {
            intName = $3 "." $5
        } else {
            intName = $3
        }
    }

    accountNum = gensub(/.*%([0-9A-Za-z]+)%.*/, "\\1", "g", $0)
    gsub(/ /, "", accountNum)

    #If the variable accountNum still contains the word description then the substitution failed so try looking
    #for the account number between "|" pipe characters.
    if(accountNum ~ /description/) {
        accountNum = gensub(/.*\|([0-9A-Za-z]+)\|.*/, "\\1", "g", $0)
        
        #The breadkdown of this statement is if the variable account number contains the string "description"
        #then that means that the substitution failed and so the variable will just contain the record text. If
        #that is the case then the account number is set to "N/A".
        interfaces[intName".accountNum"] = (accountNum !~ /description/) ? accountNum : "N/A"
    } else {
        interfaces[intName".accountNum"] = accountNum
    }

    interfaces[intName".description"] = gensub(/.*description (.*)/, "\\1", "g")

    gsub("\"", "", interfaces[intName".description"])
}

#S. Pierce - Added support for storing 802.1q VLAN tags July 2nd 2018
#Stores one tag if found, otherwise if a second tag is found it includes the second with a "%" delimiter
/^interfaces (inactive: )?[^ ]+ (unit [0-9]+ )?vlan-/ {

    intName = ""
    vlanTags = ""

    if($2 != "inactive:") {
        if($3 == "unit") {
            intName = $2 "." $4     
            if($0 ~ /vlan-tags/) {
                if($8 ~ /inner/) {
                    vlanTags = $7 "%" $9
                } else {
                    vlanTags = $7
                }
            }
        } else {
            intName = $2  
            if($0 ~ /vlan-tags/) {
                if($6 ~ /inner/) {
                    vlanTags = $5 "%" $7
                } else {
                    vlanTags = $5
                }
            }
        }
    } else {
        if($4 == "unit") {
            intName = $3 "." $5
            if($0 ~ /vlan-tags/) {
                if($9 ~ /inner/) {
                    vlanTags = $8 "%" $10
                } else {
                    vlanTags = $8
                }
            }
        } else {
            intName = $3
            if($0 ~ /vlan-tags/) {
                if($7 ~ /inner/) {
                    vlanTags = $6 "%" $8
                } else {
                    vlanTags = $6
                }
            }
        }
    }


    if($0 ~ /vlan-id/) {
        vlanTags = $NF
    }

    interfaces[intName".vlanTags"] = vlanTags
}


#This section will extract the QoS policy out of an interface that has one directly applied to it.
/^interfaces (inactive: )?[^ ]+ (unit [0-9]+ )?family inet policer output/ {
    intName = ""

    if($2 != "inactive:") {
        if($3 == "unit") {
            intName = $2 "." $4
        } else {
            intName = $2    
        }
    } else {
        if($4 == "unit") {
            intName = $3 "." $5
        } else {
            intName = $3
        }
    }

    interfaces[intName".QoS"] = $NF " (family inet policer)"
}

#This section will take all of the interfaces of an interface set and apply the QoS policy of the interface set to each interface in the
#set.
/class-of-service interfaces (interface-set)?.*(output-traffic-control-profile|scheduler-map)/ {
    #If this record contains the phrase "interface-set" then the set of interfaces in it will have the QoS policy applied.
    #In these records the QoS policy name will be the last field in the record.
    if($3 == "interface-set") {
        setName = $4

        numInterfaces = split(interfaceSets[setName], interfacesInSet, ",")

        #This loop will iterate through the number of interfaces in the interface set and apply the QoS policy
        #to each.
        for(i = 1; i <= numInterfaces; i++) {
            interface = interfacesInSet[i]
            interfaces[interface".QoS"] = "interface-set " setName " traffic-control-profile " $NF 
        }
    } else {
        if($4 = "unit") {
            intName = $3 "." $5
        } else {
            intName = $3
        }

        #For class-of-service configurations for single interfaces, the QoS policy could be applied via a scheduler-map or
        #via a traffic-control-profile. The policy type will always be te second to last field in the record.
        policyType = $(NF - 1)

        if(policyType == "scheduler-map") {
            interfaces[intName".QoS"] = "scheduler-map " $NF
        } else {
            interfaces[intName".QoS"] = "traffic-control-profile " $NF
        }      
    }
}

#The ip routes will be assigned to their interfaces in this section.
/^(routing-instances [^ ]+ )?routing-options static route [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\/[0-9]+ next-hop/ {
    #This will hold the number of next hops in the record. Sometimes routes will have more than 1 next hop in juniper configs
    #so iteration needs to happen on all of them.
    numNextHops = 0
    #This will hold the list of next hops in the record.
    nextHops = ""
    #This will hold the vrf tag for any vrf routes.
    vrfLabel = ""
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

    #Sometimes juniper routes have 2 next hops (one of the next hops may not be in the same router). If there then they need
    #to be captured in an array. If there is only 1 next hop then that one is put in the array.
    if($0 ~ /\[ .* \]/) {
        nextHops = gensub(/.*\[ (.*) \]/, "\\1", "g", $0)
        numNextHops = split(nextHops, nextHopsArr, " ")
    } else {
        nextHopsArr[1] = $NF
        numNextHops = 1
    }

    #VRF routes in junipers route configurations in Junipers start with the term "routing-instances", if the current record does
    #contain this then the route will be the 6th field in the record and the vrf tag will be the 2nd field.
    if($0 ~ /^routing-instances/) {
        vrfLabel = $2
        lanNetwork = $6
    } else {
        lanNetwork = $4
    }

    for(i = 1; i <= numNextHops; i++) {
        #If current next hop has an alphapebit character then it is an interface name so take it as the next hop to assign the route
        #to.
        if(nextHopsArr[i] ~ /[A-za-z]/) {
            intName = nextHopsArr[i]
            interfaces[intName".lan"] = removeTrailingAndLeadingCommas(interfaces[intName".lan"] "," lanNetwork)
        } else {
            #If this is not a vrf then get a list of all non vrf interfaces, otherwise get the list of all interfaces tied
            #to the vrf.
            if(vrfLabel != "") {
                numInterfaces = split(vrfTags[vrfLabel], vrfInterfaces, ",")
            } else {
                numInterfaces = split(vrfTags["none"], vrfInterfaces, ",")
            }

            nextHopDecimal = ipToDecimal(nextHopsArr[i])

            for(k = 1; k <= numInterfaces; k++) {
                intName = vrfInterfaces[k]

                #It is possible to get an interface without a wan ip so skip the entry if it does not.
                if(interfaces[intName".wan"] != "") {
                    numWans = split(interfaces[intName".wan"], wanArr, ",")

                    for(j = 1; j <= numWans; j++) {
                        networkBroadcastString = gensub(/.*%([^%]+)%/, "\\1", "g", wanArr[j])
                        split(networkBroadcastString, networkBraodcastSplit, "_")
                        networkIp = networkBraodcastSplit[1]
                        broadcastIp = networkBraodcastSplit[2]

                        #If the nexthop is between the network ip and the broadcast ip then this route must belong to the interface.
                        if((nextHopDecimal >= networkIp) && (nextHopDecimal <= broadcastIp)) {
                            interfaces[intName".cpeIp"] = nextHopsArr[i]
                            interfaces[intName".lan"] = interfaces[intName".lan"] "," lanNetwork
                            interfaces[intName".lan"] = removeTrailingAndLeadingCommas(interfaces[intName".lan"])
                        }
                    }
                }
            }
        }
    }
}

#This section will accumilate the QoS policies of all of the interfaces that are part of a bridge-domain and then all of them will be
#assigned to the routed interface of the bridge-domain.
/^bridge-domains [^ ]+ (interface|routing-interface)/ {
    intName = $NF
    bridgeDomain = $2
    intQOS = ""

    if ($0 ~ /routing-interface/) {
        interfaces[intName".QoS"] = bdArr[bridgeDomain]
    } else {
        if(interfaces[intName".QoS"] != "") {
            intQOS = interfaces[intName".QoS"] " (" intName ")"
            bdArr[bridgeDomain] = removeTrailingAndLeadingCommas(bdArr[bridgeDomain] "," intQOS)
        }

        delete interfaces[intName".QoS"]
    }

    bdArr[0]
}

##########################################################################################
# Start of getNetworkIp() function
#
# This function will be used to get the netwok ip of the ip address of an interface. What it  will do is call ipcalc
# in /bin and run it with the parameters ipaddress and mask with the -n switch which will generate the CIDR mask with
# syntax "NETWORK=X.X.X.X" where "X.X.X.X" will be the network ip address of the ipaddress and subnet mask passed in.
#
# Parameters:
#     ipaddress: The ip address of the interface (could also be used for any ip address, this function
#     will mainly be used to get the network ip of interfaces though).
#
#     mask: The subnet mask if the ipaddress in ip notation.
#
# Local Variables:
#     networkip: This variable will be used to hold the value of the calculated network ip address and will be the
#     return value for this function.
#
#     command: This variable will be used to store the ipcalc command as a string so that it can be piped to 
#     getline and will then be stored in networkip.
function getNetworkIp(ipaddress, mask,    networkip, command) {
    if(mask == "/32") {
        return ipaddress
    } else {
        command = "/home/e0163688/Scripts/IpCalc/ipcalc " ipaddress mask " | sed -n -r 's/Network: +([^ ]+) +.*/\\1/gp'"
    }

    command | getline networkip

    close(command)

    return networkip
}
# End of getNetworkIp() function
##########################################################################################

##########################################################################################
# Start of getBroadcastIp() function
#
# This function will be used to get the broadcast ip of the ip address of an interface. What it  will do is call ipcalc
# in /bin and run it with the parameters ipaddress and mask with the -b switch which will generate the CIDR mask with
# syntax "BROADCAST=X.X.X.X" where "X.X.X.X" will be the broadcast ip address of the ipaddress and subnet mask passed in.
#
# Parameters:
#     ipaddress: The ip address of the interface (could also be used for any ip address, this function
#     will mainly be used to get the broadcast ip of interfaces though).
#
#     mask: The subnet mask if the ipaddress in ip notation.
#
# Local Variables:
#     broadcastip: This variable will be used to hold the value of the calculated broadcast ip address and will be the
#     return value for this function.
#
#     command: This variable will be used to store the ipcalc command as a string so that it can be piped to 
#     getline and will then be stored in broadcastip.
function getBroadcastIp(ipaddress, mask,    broadcastip, command) {
    if(mask == "/32") {
        return ipaddress
    } else if(mask == "/31") {
        command = "/home/e0163688/Scripts/IpCalc/ipcalc " ipaddress mask " | sed -n -r 's/HostMax: +([^ ]+) +.*/\\1/gp'"
    } else {
        command = "/home/e0163688/Scripts/IpCalc/ipcalc " ipaddress mask " | sed -n -r 's/Broadcast: +([^ ]+) +.*/\\1/gp'"
    }

    command | getline broadcastip

    close(command)

    return broadcastip
}
# End of getBroadcastIp() function
##########################################################################################

##########################################################################################
# Start of ipToDecimal() function
#
# This function will be used to take an ip address and turn it into a decimal number. This will be usefull in determining
# if an ip address falls witin a range of ips (like if an ip falls between a network ip and a broadcast ip). The formula for
# this is the one below:
#     (first octet * 256�) + (second octet * 256�) + (third octet * 256) + (fourth octet)
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
    intRecord = ""
    digCustFile = "/home/e0163688/Scripts/DigCust/digCUST.db-tmp"

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
