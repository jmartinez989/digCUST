#!/bin/gawk -f
#############################################################################
# checkvrf.awk
#
# Author: Joy Martinez
#
# This is a very simple awk script that will be used in script digCUST. The
# input for this script will be a set of records from the digCUST database.
# This script will take each record and check its vrf field and compare it to
# the name of the vrf passed in as a variable to awk. If it finds any record
# with a vrf that is different to one passed in it prints a message stating
# this and exits with status code 2.
#############################################################################

#############################################################################
# BEGIN PROCEDURE
# Setting up all constants and globals
BEGIN {

    if(!vrf) {
        print "Usage: checkvrf.awk -v vrf=\"vrf-name\" -v noascii=(0 or 1){optional} *inputfile*"
        exit 2
    }

    #Change field separator as the fields will be delimited by ":::" character sequence.
    FS = ":::"

    ########################
    # CONSTANTS
    ########################
    #Setting up color escape character modifiers
    CYAN = "\033[36m"

    #Setting up modifier terminator
    TERM = "\033[0m"

    vrfText = (noascii) ? vrf  : CYAN vrf TERM
}
# END OF BEGIN PROCEDURE
#############################################################################

#When this script is called it will have it's input piped where the input has the vrf tag
#stored in it. If the piped input is empty there will be no records which means the vrf tag
#used did not return an results so the error message is printed out.
NF == 0 {
    printErrorMessage()
}

#This will check every record and see if the vrf field is the same as the vrf passed in as a
#variable.
{
    vrfField = gensub(/"/, "", "g", $5)

    if(vrfField != vrf) {
        printErrorMessage()
    }
}

function printErrorMessage() {
    print "Invalid vrf: " vrfText ". Please make sure that you have typed the vrf exactly the way it is provsioned for"
    print "the customer (vrf names are case sensitive, they need to be character for character the same)."
    exit 2
}
