


for region in $(ibmcloud regions -q |tail -n +2 |awk '{print $1}'); do ibmcloud target -r $region -q; ibmcloud is floating-ips -q |awk '{print $1}'); done