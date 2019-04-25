#!/bin/gawk -f
#############################################################################
# checkvrf.awk
#
# Author: Joy Martinez
#
# A simple awk script that will read in the file csvgreet which is a file
# that will be displayed from the digCUST script when the -csv flag is supplied
# to that script. What this will do is take the csv file and find any instances
# of the character sequence [|vrf|] or [|date|] and replace them with the
# values of the respective varaibles passed in via the awk parameter line (the
# variable names are vrf and fileDate).
#############################################################################

#############################################################################
# BEGIN PROCEDURE
# Setting up all constants and globals
BEGIN {

    if(!vrf || !fileDate) {
        print "Usage: printgreet.awk -v vrf=\"vrf-name\" -v fileDate=\"dateFileModified\" -v noascii=(0 or 1){optional} csvfile"
        exit
    }

    ########################
    # CONSTANTS
    ########################
    #Setting up color escape character modifiers
    CYAN = "\033[36m"
    YELLOW = "\033[33m"

    #Setting up modifier terminator
    TERM = "\033[0m"    
}
# END OF BEGIN PROCEDURE
#############################################################################

#This will match any lines that have the text [|vrf|] in them. It will replace them with the contents
#of the variable "vrf" that is passed into the script (along with the ANSI characters so that color
#is displayed properly).
/\[\|vrf\|\]/ {
    if(noascii) {
        gsub(/\[\|vrf\|\]/, vrf)
    } else {
        gsub(/\[\|vrf\|\]/, CYAN vrf TERM)
    }
}

#This will match any lines that have the text [|date|] in them. It will replace them with the contents
#of the variable "fileDate" that is passed into the script (along with the ANSI characters so that color
#is displayed properly).
/\[\|date\|\]/ {
    if(noascii) {
        gsub(/\[\|date\|\]/, fileDate)
    } else {
        gsub(/\[\|date\|\]/, YELLOW fileDate TERM)
    }
}

#This will just print out every record. This will also print the modified records mathched above.
{
    print
}
