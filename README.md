# sw-report.sh
<p>Quickly lookup Brocade SAN Fabric switch information using CLI. This was initially created to collect switch fabric information during troubleshooting, which usually required multiple commands to finally extract what I was looking for. The script automates this, saving a great deal of time, to focus on the issue instead of list of commands, filters, and adhoc scripts needed to get the same result.</p>
<p>This program includes a number of very useful functions, such as...</p>

* Display the current list of switches and directors on the SAN Fabrics by name and IP, so you don't have to look this up from your notes, or an internal webpage. Switch firmware versions are included. This is automatically updated, as switches are added or removed. <b>Note:</b> The script requires an update if the core fabric switches are changed.
* Enhanced switchshow command which includes all the Virtual WWPNs and their hostnames on the same port. If any portnames were defined, they're also included. 
* Enhanced porterror report which only displays the ports with errors, along with an explanation of each, shrinking this report length significantly when viewing Directors.
* Search the entire SAN Fabric to identify the switch and ports used by any host, storage array or ISL. Quite useful when troubleshooting port failures. 
* Display all zones containing a host, array alias or port WWN you define using a search key. If no keys were used, then every zone and their respective alias members are shown.

<p>All functions allow up to 2 additional search keys to help narrow down results. The intent here is to help quickly identify "the needle in the haystack".</p>

    $ sw-report.sh
    usage: sw-report.sh [list] | [<Switch_Name|IP_Address> [porterror]] | [find port|alias|zone [-]<key1> [[-]<key2>]]

    $ sw-report.sh list
    IP Address     Firmware  Switch Name
    -------------  --------  -----------
    192.168.0.100  v8.2.3d   switch1
    192.168.0.101  v8.2.3d   switch2
    192.168.0.200  v9.2.0a   switch3
    ...

    $ sw-report.sh switch1 prod_app
    switch1:

    Index  Slot  Port  Speed  State      Port Name                            WWN Address              WWN Alias / Node Info / Trunk Info
    -----  ----  ----  -----  ---------  -----------------------------------  -----------------------  ----------------------------------
      10    --    10    N16   Online     prod_app1                            10:00:00:00:00:00:00:a0  prod_app1_hba1
      15    --    15    N16   Online     prod_app2                            10:00:00:00:00:00:00:a1  prod_app2_hba1

    $ sw-report.sh find port test_app3
    switch8:

    Index  Slot  Port  Speed  State      Port Name                            WWN Address              WWN Alias / Node Info / Trunk Info
    -----  ----  ----  -----  ---------  -----------------------------------  -----------------------  ----------------------------------
      22    --    22    N16   Online     test_app3                            10:00:00:00:00:00:00:c2  test_app3_hba1

    $ sw-report.sh find zone prod_app1
    fabric_a:
    zone: array1_CL1A
                    50:06:00:00:00:00:00:10  array1_CL1A
                    10:00:00:00:00:00:00:a0  prod_app1_hba1

    fabric_b:
    zone: array1_CL2A
                    50:06:00:00:00:00:00:10  array1_CL2A
                    10:00:00:00:00:00:00:b0  prod_app1_hba2
    ...

    $ sw-report.sh 192.168.0.101 porterror
    Please wait - reading SAN configuration.
      switch IP and names.....
      switch firmware.....

    switch1:

              frames        enc     crc     crc     too     too     bad     enc    disc    link     loss     loss    frjt    fbsy     c3timeout       pcs    uncor
            tx      rx       in     err     g_eof   shrt    long    eof     out    c3      fail     sync     sig                      tx      rx      err     err
      16:    0       0       0       0       0       0       0       0       0       0       1.0m     1.0m     0       0       0       0       0       0       0

    link fail      Link Failures (LF1 or LF2 state).
                   The number of times the port achieved Link Fail 1 and/or Link Fail 2 states.

    loss sync      Loss of Synchronization.
                   Caused by host reboot, storage sub-system power cycle, cable disconnect, or portDisable command.

    $
