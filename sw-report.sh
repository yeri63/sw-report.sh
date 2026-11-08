#! /bin/bash

# Program: sw-report.sh
# Version: 2.56
#    Date: 02-Sep-2025
#  Author: gerry.walterscheid@gmail.com

# Description:
#
# Display helpfull switch information for fabric management and troubleshooting.


# Global Constants

user=`echo $USER`                                   # Requires user id with sshkey enabled on every switch.

path=/home/$user
script=sw-report.sh                                 # Script name shown in messages.
fabric=( 192.168.0.100 192.168.0.200 )              # Fabric A and B switch IP's.

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

read_config ()
{
    n=0

    echo
    echo "Please wait - reading SAN configuration."
    echo -n "  switch IP and names..."

    for switch_ip in ${fabric[@]}; do				# Collect switch IP and names.
        for switch in `ssh $user@$switch_ip fabricshow | awk '
            /0.0.0.0/ { if ( $4 != "0.0.0.0" ) {
                            split($6,a,"\"");
                            printf("%s:%s\n", $4, a[2]); } }' `; do
            ip[n]=${switch%:*}
            name[n]=${switch#*:}
 
            (( n++ ))
        done
        echo -n "."
    done 

    echo
    n=0

    echo -n "  switch firmware..."

    for switch_ip in ${fabric[@]}; do				# Collect switch firmware.
        for switch_fw in `ssh $user@$switch_ip "fabricshow -version" | awk '
            /0.0.0.0/ { if ( $4 != "0.0.0.0" ) 
                            print $6 }' `; do
            fw[n]=$switch_fw
 
            (( n++ ))
        done
        echo -n "."
    done 

    echo
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

list_switches ()
{
    echo
    echo "IP Address     Firmware  Switch Name"
    echo "-------------  --------  -----------"

    for (( i=0; i<n; i++ )); do
        printf "%-13s  %-8s  %-20s\n" ${ip[i]} ${fw[i]} ${name[i]} 
    done

    echo
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

validate ()
{
    for (( i=0; i<n; i++ )); do					# Validate the switch IP/name.
        if [ "$1" == "${ip[i]}" ] || [ "$1" == "${name[i]}" ]; then
            return
        fi
    done

    param_error "non-existent switch or invalid option"
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

findPort ()
{
    read_config

    for (( i=0; i<n; i++ )); do

        switch_info ${name[i]} | awk -v key1="$1" -v key2="$2" '

            BEGIN  { key1 = tolower(key1);
                     key2 = tolower(key2);
                     inv1 = 0;
                     inv2 = 0;

                     if (substr(key1,1,1) == "-") {
                         key1 = substr(key1,2,length(key1)-1);
                         inv1 = 1; } 

                     if (substr(key2,1,1) == "-") {
                         key2 = substr(key2,2,length(key2)-1);
                         inv2 = 1; } }

            NR < 6 { line[n++] = $0; }

            NR > 5 { data = tolower($0);

                     if ( ((inv1 == 0) && (inv2 == 0) && match(data, key1) && match(data, key2)) ||
                          ((inv1 == 1) && (inv2 == 0) && !match(data, key1) && match(data, key2)) ||
                          ((inv1 == 0) && (inv2 == 1) && match(data, key1) && !match(data, key2)) ||
                          ((inv1 == 1) && (inv2 == 1) && !match(data, key1) && !match(data, key2)) )
                         line[n++] = $0; }
            
            END    { if (n > 5) 
                         for (i = 0; i < n; i++)
                             print line[i]; }'
    done

    echo
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

switch_info ()
{
    { switch=$1
      echo $switch

      ssh $user@$switch ' alishow *;                            # Collect alias and WWN data.
                          portname;                             # Collect switch portname data.
                          switchshow;                           # Collect switch connections.
                          nsshow; '                             # Collect Name Server data.

      } | awk -v OFS='\t' '
          BEGIN { getline;
                  switch_name = $0;                             # Record switch name.
                  getline;

                  while ( length($0) > 0 ) {                    # Process alishow data.
                      if ( match($0, "alias") ) {
                          alias_data = $2;
                          getline;
                          pwwn_data = $1; 

                          pwwn[alias_data] = pwwn_data;
                          alias[pwwn_data] = alias_data; }
                      getline; }

                  getline;

                  while ( !match($0, "switchName:") ) {         # Process portname data.

                      # Skip empty ports.

                      if ( !match($0, ": slot") && !match($0, ": port") ) {	
                          split($2,a,":");
                          i = a[1];
                          max_i = i;
                          portname_data = $3;
                          portname[i] = portname_data; }

                      getline; }

                  getline;

                  # Added since newer Directors have indexes which are not sequentially ordered 
                  # with their related slot and ports.

                  p = 0;                                        # Initialize record pointer.

                  while ( !match($0, "{") && ( FNR != LastRec ) ) {			# Process switchshow data.

                      LastRec = FNR;                            # Added to eliminite infinte loops.

                      if ( match($0, "Slot") ) {        		# Determine switch type.
                          blade_switch = "y" }

                      if ( match($0, " id ") || match($0, " -- ") ) {
                          rec[p] = $1;                          # Switch port record.
                          max_p = p;

                          i = $1;                               # Port index.

                          if ( blade_switch == "y" ) {
                              slot[i] = $2;
                              port[i] = $3;
                              speed[i] = $6; 
                              state[i] = $7; 
                              status[i] = $9; }
                          else {
                              port[i] = $2;
                              speed[i] = $5;
                              state[i] = $6; 
                              status[i] = $8; }

                          if ( match($0, "E-Port") ) 
                              for (j = 9; j < 22; j++)  # Collect Trunk Info.
                                  if ( $j != "E-Port" && $j != "LD" )	
                                      if ( match($j,":") )
                                          node[i] = $j;
                                      else
                                          notes[i] = notes[i] $j " ";

                          p++ }                                    # Advance record pointer.

                      getline; } 
                } 

          # Process Name Server data containing potential NPIV entries.

          / N / { split($0,a,";");
                  node_pwwn = a[3]; }                          # WWN node

          /NodeSymb/ { split($0,a,"\"");
                       node_info[node_pwwn] = a[2]; }

          /Index/ { i = $3;
                    if ( length(node[i]) == 0 )
                        node[i] = node_pwwn
                    else 
                        node[i] = node[i] ";" node_pwwn;

#  print i, node[i];

                    }

          END { # Print table headings.

                printf("\n");
                printf("%s:\n", switch_name);
                printf("\n");
                printf("Index  Slot  Port  Speed  State      Port Name                            ");
                printf("WWN Address              WWN Alias / Node Info / Trunk Info\n");
                printf("-----  ----  ----  -----  ---------  -----------------------------------  ");
                printf("-----------------------  ----------------------------------\n");

                last_slot = 0;

                for (p = 0; p <= max_p; p++) {
                    i = rec[p];

                    if ( status[i] == "Disabled" )
                        continue;
                        
                  #  if ( length(portname[i]) > 0 ) 
                        nodes = split(node[i],npiv,";");

                        if ( (slot[i] > last_slot) && (last_slot > 0) )             # Separate each slot with linefeed.
                            printf("\n");

                        if ( nodes <= 1 ) {			# Non-NPIV node.
                            if ( blade_switch == "y" )
                                printf("%4d   %3d   %3d   ", i, slot[i], port[i])
                            else
                                printf("%4d   %3s   %3d   ", i, "--", port[i]);

                            printf("%4s   ", speed[i]);
                            printf("%-9s  ", state[i]);
                            printf("%-35s  ", portname[i]);
                            printf("%-23s  ", node[i]);

                            if ( length(notes[i]) > 0 )
                                printf("%s\n", notes[i]);
                            else 
                                printf("%s\n", alias[node[i]]); }
                        else
                            for (j = 1; j <= nodes; j++) {	# NPIV nodes.
                                if ( blade_switch == "y" )
                                    printf("%4d   %3d   %3d   ", i, slot[i], port[i])
                                else
                                    printf("%4d   %3s   %3d   ", i, "--", port[i]);

                                printf("%4s   ", speed[i]);
                                printf("%-9s  ", state[i]);
                                printf("%-35s  ", portname[i]);
                                printf("%-23s  ", npiv[j]);

                                if ( length(alias[npiv[j]]) > 0 )
                                    printf("%s\n", alias[npiv[j]])
                                else
                                    printf("%s\n", node_info[npiv[j]]); }

                        last_slot = slot[i]; # }
                    }
               }'

    echo
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

findAlias ()
{
    echo

    for switch_ip in ${fabric[@]}; do
        { ssh $user@$switch_ip "cfgshow | grep cfg" | sed '$d';
          ssh $user@$switch_ip "alishow *" | sed '$d'; } | awk -v key1="$1" -v key2="$2" '

              BEGIN { key1 = tolower(key1);
                      key2 = tolower(key2);
                      inv1 = 0;
                      inv2 = 0;

                     if (substr(key1,1,1) == "-") {
                         key1 = substr(key1,2,length(key1)-1);
                         inv1 = 1; } 

                     if (substr(key2,1,1) == "-") {
                         key2 = substr(key2,2,length(key2)-1);
                         inv2 = 1; } 

                      getline;
                      printf("%s:\n", $2);

                      RS = " alias:";
                      getline;
                      found = 0; }

              { data = tolower($0);

                if ( ((inv1 == 0) && (inv2 == 0) && match(data, key1) && match(data, key2)) ||
                     ((inv1 == 1) && (inv2 == 0) && !match(data, key1) && match(data, key2)) ||
                     ((inv1 == 0) && (inv2 == 1) && match(data, key1) && !match(data, key2)) ||
                     ((inv1 == 1) && (inv2 == 1) && !match(data, key1) && !match(data, key2)) ) {

                    if (found == 0)                     # Add linefeed between command
                        print " ";                      # and results.

                    printf(" alias:%s", $0) 
                    found = 1; } }

              END { if (found  == 0) 
                        print "Alias not found."; }'
        echo
    done

    exit 0
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

findZone ()
{
    echo

    for switch_ip in ${fabric[@]}; do

        { ssh $user@$switch_ip "cfgshow | grep cfg" | sed '$d';
          ssh $user@$switch_ip "alishow *; 
                                cfgactvshow"; } | awk '

        # Populate pwwn and alias tables, used to show both member alias and pWWN.

        BEGIN { getline;
                print $2;                                   # Switch fabric.

                getline;
                while ( length($0) > 0 ) {
                    if ( match($1, "alias") ) {
                        name = $2;

                        # If the alias is short, it will include the WWN on same line.
                        if ( NF < 3 ) {
                            item = 1;  
                            getline; }
                        else
                            item = 3;

                        # Capture multiple WWNs if they exist.
                        for ( i = item; i <= NF; i++) {
                            # Remove trailing ; if present.
                            wwn = substr($i,0,23); 
                            alias[wwn] = name; } 
                        }

                    getline; }
                
                # Skip the 1st 3 lines of next report. 
                getline;
                getline;
                getline; }

        # Process cfgactvshow data, looking up the alias from the pWWN.

        /zone/ { printf("\n %s %s\n", $1, $2); } 

        !/zone/ { if (length( $0 ) > 0 ) {
                      wwn = $1;
                      name = alias[wwn];                     # Lookup alias.

                      if ( length(name) == 0 )
                          name = "(undefined)";

                      printf("                %16s  %s\n", wwn, name); }
                }

        END { print " " }' | awk -v key1="$1" -v key2="$2" '

        BEGIN { key1 = tolower(key1);
                key2 = tolower(key2);
                inv1 = 0;
                inv2 = 0;

                if (substr(key1,1,1) == "-") {
                    key1 = substr(key1,2,length(key1)-1);
                    inv1 = 1; } 

                if (substr(key2,1,1) == "-") {
                    key2 = substr(key2,2,length(key2)-1);
                    inv2 = 1; } 

                getline;
                printf("%s:\n", $1);

                RS = " zone:";
                getline;  
                found = 0; }

        { data = tolower($0);

          if ( ((inv1 == 0) && (inv2 == 0) && match(data, key1) && match(data, key2)) ||
               ((inv1 == 1) && (inv2 == 0) && !match(data, key1) && match(data, key2)) ||
               ((inv1 == 0) && (inv2 == 1) && match(data, key1) && !match(data, key2)) ||
               ((inv1 == 1) && (inv2 == 1) && !match(data, key1) && !match(data, key2)) ) {

              if (found == 0) 
                  print " ";

              printf(" zone:%s", $0); 
              found = 1; } }
 
        END { if (found  == 0) 
                  print "Zone not found.\n"; }'

    done

    exit 0
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

porterrshow ()
{
    ssh $user@${name[i]} porterrshow | awk -v switch_name=${name[i]} '
        BEGIN { error[4] = "enc in"
                mesg1[4] = "Encoding errors inside frames."
                mesg2[4] = "Replace the cable or SFP, move cable to another port, or run porttest."

                error[5] = "crc err"
                mesg1[5] = "Frames with CRC (Cyclic Redundancy Check) errors."
                mesg2[5] = "Replace the cable or SFP, move cable to another port, or run porttest."

                error[6] = "crc g_eof"
                mesg1[6] = "CRC (Cyclic Redundancy Check) errors that occur on frames with good end-of-frame delimeters."
                mesg2[6] = "The transmitter or path from the originating link may be generating the errors."

                error[7] = "too shrt"
                mesg1[7] = "Frames shorter than minimum."
                mesg2[7] = "Caused by the transmitter, or an unreliable link."

                error[8] = "too long"
                mesg1[8] = "Frames were longer than maximum."
                mesg2[8] = "Caused when an EOF is corrupted or data generation in incorrect."

                error[9] = "bad eof"
                mesg1[9] = "Frames with bad end-of-frame delimiters."
                mesg2[9] = "Caused by invalid CRC or missing EOF delimiter."

                error[10] = "enc out"
                mesg1[10] = "Encoding errors outside of frames."
                mesg2[10] = "Caused by host reboot, storage sub-system power cycle, cable disconnect, or portDisable command."

                error[11] = "disc c3"
                mesg1[11] = "Class 3 frames discarded."
                mesg2[11] = "Class 3 frames discarded due to timeouts, invalid, unreachable destinations, or port congestion."

                error[12] = "link fail"
                mesg1[12] = "Link Failures (LF1 or LF2 states)."
                mesg2[12] = "The number of times the port achieved Link Fail 1 and/or Link Fail 2 states."

                error[13] = "loss sync"
                mesg1[13] = "Loss of Synchronization."
                mesg2[13] = "Caused by host reboot, storage sub-system power cycle, cable disconnect, or portDisable command."

                error[14] = "loss sig"
                mesg1[14] = "Loss of Signal."
                mesg2[14] = "Caused by host reboot, storage sub-system power cycle, cable disconnect, or portDisable command."

                error[15] = "frjt"
                mesg1[15] = "Fabric Port Reject Frames."
                mesg2[15] = "The delivery of a frame is being denied due to unsupported class, invalid header field, or unavailable N-Port."

                error[16] = "fbsy"
                mesg1[16] = "Fabric Port Busy Frames."
                mesg2[16] = "Issued by the Fabric when Frame cannot be delivered because the Fabric or destination N-Port is busy."

                error[17] = "c3timeout tx"
                mesg1[17] = "Class 3 transmit frames discarded due to timeout."
                mesg2[17] = "Caused by a problem downstream of this port or a frame meant to be forwarded to another port on the same switch."

                error[18] = "c3timeout rx"
                mesg1[18] = "Class 3 receive frames discarded due to timeout."
                mesg2[18] = "Caused by a problem downstream of this port or a frame meant to be forwarded to another port on the same switch."

                error[19] = "pcs err"
                mesg1[19] = "Physical Coding Sublayer."
                mesg2[19] = "Caused by encoding errors on 16G platforms and above."

                error[20] = "uncor err"
                mesg1[20] = "Uncorrectable Forward Error Corrections (FEC)."
                mesg2[20] = "The receiving device was unable to correct a burst of corrupted bits in the frame using FEC parity data." 

                tot_errors = 0;
                line = 0;
        }

        /in/ { report[line++] = $0; }				# Report heading.

        /:/ { errors = 0;

          for (i = 4; i <= NF; i++) 
              if ($i) { 
                  errors = 1;
                  tot_errors++;
                  err_type[i] = 1; }

              if (errors) 
                  report[line++] = $0; }			# Report detail line containing error.

        END { if (line == 2) {					# Exit if no errors found, ie. only heading collected.
                  printf("No errors found.\n\n");
                  exit 0; }

              printf("\n"); 
              printf("%s:\n", switch_name);
              printf("\n");

              for (i = 0; i < line; i++)			# Print out body of report.
                  print report[i];

              if (tot_errors > 0) {				# Print help for errors found.
                  print " ";

                  for (i = 4; i < 21; i++) 
                      if (err_type[i]) {
                          printf("%-14s %s\n", error[i], mesg1[i]);
                          printf("%-14s %s\n\n", " ", mesg2[i]); }
                  }
            }'
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

param_warning ()
{
    echo "warning: "$1"."
    echo
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

param_error ()
{
    echo "error: "$1"."
    echo
    exit 1
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

usage_error ()
{
    echo "usage: $script [list] | [<Switch_Name|IP_Address> [porterror]] | [find port|alias|zone [-]<key1> [[-]<key2]]"
    echo
    exit 1
}

# ------- --------- --------- --------- --------- --------- --------- --------- --------- ---------

# Begin script execution here.

if [ $# -eq 0 ]; then
    usage_error
fi

if [ "`whoami`" == "root" ]; then      # Allow to run script when logged in as root.
    sudo -u $user $path/$script "$@"
    exit 0
fi

if [ "$1" == "find" ]; then
    if [ "$2" == "port" ]; then
        findPort $3 $4 
        exit 0

    elif [ "$2" == "alias" ]; then
        findAlias $3 $4
        exit 0

    elif [ "$2" == "zone" ]; then
        findZone $3 $4
        exit 0

    else
        param_error "missing parameter type (port, alias or zone)"
    fi
fi

read_config							    # Read switch mgmt access config.

if [ "$1" == "list" ]; then             # Display current list of switches.
    if [ $# -gt 1 ]; then
        param_warning "extra parameters ignored"
    fi

    list_switches
    exit 0
fi

if [ $# -eq 1 ]; then
    validate $1							# Validate switch IP/name.

    switch_info ${name[i]}              # Display ports used, WWN, and alias.
    exit 0
fi

if [ "$2" == "porterror" ]; then
    validate $1							# Validate switch IP/name.

    porterrshow							# Display port errors.
    exit 0
fi

usage_error

