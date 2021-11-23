#!/bin/bash
#
#
#     Created by A.Hodgson
#      Date: 10/26/2021
#      Purpose: Enable Lost mode to multiple iOS devices via a list in Google Sheets (Spreadsheet needs "Anyone with link access")
#  
#
#############################################################

##############################################################
# # server API connection information
URL=""
userName=""
password=""
# Get the List from Google
spreadsheet_id="" #Spreadsheet needs "Anyone with link access"
#############################################################
# User Prompts
PromptIcon="/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns"

lostModeMsg=$(/usr/bin/osascript -e "
on run
display dialog \"Please enter your Lost Mode message (Required):\" default answer \"\" with title \"Lost Mode En Masse\" buttons {\"Ok\"} default button 1 with icon POSIX file \"$PromptIcon\"
set userTxt to text returned of the result
return userTxt
end run")

lostModePhone=$(/usr/bin/osascript -e "
on run
display dialog \"Please enter your Lost Mode phone number (Required):\" default answer \"\" with title \"Lost Mode En Masse\" buttons {\"Ok\"} default button 1 with icon POSIX file \"$PromptIcon\"
set userTxt to text returned of the result
return userTxt
end run")

lostModeFootnote=$(/usr/bin/osascript -e "
on run
display dialog \"Please enter your Lost Mode foot note (Optional):\" default answer \"\" with title \"Lost Mode En Masse\" buttons {\"Ok\"} default button 1 with icon POSIX file \"$PromptIcon\"
set userTxt to text returned of the result
return userTxt
end run")

message="Confirm your details are correct: 
Message: $lostModeMsg

Phone: $lostModePhone

Footnote: $lostModeFootnote"
osascript -e "display dialog \"$message\" with title \"Lost Mode En Masse\" buttons {\"Cancel\", \"OK\"} default button 2";
# Check status of osascript
if [ "$?" != "0" ] ; then
   echo "User aborted. Exiting..."
   exit 1
fi

##############################################################
# Confirm Devices
osascript <<'END'
    display dialog "Please confirm your device list is correct, and the first tab" buttons {"Psh, I'm good", "Cancel"} default button "Psh, I'm good" giving up after 60
    set the button_pressed to the button returned of the result
END

sleep 5

osascript <<'END'
    set theAlertText to "Seriously...."
    set theAlertMessage to "This is your last chance. Press the All Systems Go button to issue Lost Mode commands."
    display alert theAlertText message theAlertMessage as critical buttons {"Cancel", "All Systems Go"} default button "All Systems Go" cancel button "Cancel" giving up after 60
    set the button_pressed to the button returned of the result
END

# Check status of osascript
if [ "$?" != "0" ] ; then
   echo "User aborted. Exiting..."
   exit 1
fi
##############################################################
csv_file="/var/tmp/csv_file.csv"
deviceList="/var/tmp/deviceList.csv"

# Check for an existing file
if [ -e "$deviceList" ]; then
  rm -f $deviceList
fi

# download the list, change permissions and elimnate all the ghost formatting from Google
curl -s -o $csv_file https://docs.google.com/spreadsheets/d/$spreadsheet_id/gviz/tq?tqx=out:csv
chmod 777 $csv_file
awk '{gsub(/\"/,"")};1' $csv_file  > /var/tmp/deviceList.csv

##############################################################
#
# Main Function
#
##############################################################

# Process devices into variable
mobileDeviceList=$( /bin/cat "$deviceList" )

successList=""

# send Lost Mode command to every device in mobile device list
for aDevice in ${mobileDeviceList[@]}
do
    # get Jamf Pro ID for device
    xml_response=$( curl -sku "$userName:$password" -H "Accept: application/xml" $URL/JSSResource/mobiledevices/serialnumber/$aDevice -X GET )
    
cat << EOF > /tmp/stylesheet.xslt
<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
    <xsl:output method="text"/>
    <xsl:template match="/">
        <xsl:for-each select="mobile_device/general">
            <xsl:value-of select="id"/>
        </xsl:for-each>
    </xsl:template>
</xsl:stylesheet>
EOF
    deviceID=$( echo "$xml_response" | xsltproc /tmp/stylesheet.xslt - )


    # API submission command
    xmlData="<mobile_device_command>
                <general>
                    <command>EnableLostMode</command>
                    <lost_mode_message>$lostModeMsg</lost_mode_message>
                    <lost_mode_phone>$lostModePhone</lost_mode_phone>
                    <lost_mode_footnote>$lostModeFootnote</lost_mode_footnote>
                    <always_enforce_lost_mode>true</always_enforce_lost_mode>
                    <lost_mode_with_sound>false</lost_mode_with_sound>
                </general>
                <mobile_devices>
                    <mobile_device>
                        <id>$deviceID</id>
                    </mobile_device>
                </mobile_devices>
            </mobile_device_command>"
    
    echo "Sending Enable Lost Mode Command to Serial: $aDevice, Device ID: $deviceID"
    api_response=$(curl --write-out %{http_code} -sku "$userName":"$password" -H "Content-Type: text/xml" -o /dev/null -d "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>$xmlData" $URL/JSSResource/mobiledevicecommands/command/EnableLostMode -X POST )
    echo "$api_response"
    if [[ "$api_response" == "200" || "$api_response" == "201" ]]
    then
       successList+="${aDevice}, "
    else
        message="Failed to enable Lost Mode on $aDevice."
        osascript -e 'display dialog "'"$message" -e '"buttons {"OK"} default button 1';
    fi
done
##############################################################
# Remove downloaded files
rm -f $deviceList
rm -f $csv_file

if [ ! -z "$successList" ]; then
    message="Successfully enabled Lost Mode on the following devices: $successList"
    osascript -e 'display dialog "'"$message" -e '"buttons {"OK"} default button 1';
fi
message="You earned a break. Good Job!"
osascript -e 'display dialog "'"$message" -e '"buttons {"All Done"} default button 1';
exit 0
