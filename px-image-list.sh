#!/usr/bin/env bash
usage()
{
cat << EOF

Usage: $0 -k (Kubernetes Version) -p (Portworx Version)
Example: $0 -k 1.24.1 -p 3.0.4

OPTIONS:
   -h      Show this message
   -k      Kubernetes Version in form x.y.z (1.24.1)
   -p      Portworx Version, example 2.13, 2.11.6

EOF
}

kbver=
pxver=

while getopts h?k:p: flag
do
    case "${flag}" in
        h)
            usage
            exit 1
            ;;
        k) kbver=${OPTARG};;
        p) pxver=${OPTARG};;
        ?)
            usage
            exit
            ;;
    esac
done
if [[ -z $kbver ]] || [[ -z $pxver ]]
then
     usage
     exit 1
fi

unset aglist
unset cmlist
unset declared_list
unset undeclared_list

# Get the air-gapped install script and parse it
aglist=$(curl -sL "https://install.portworx.com/${pxver}/air-gapped?kbver=${kbver}"|grep ^IMAGES|cut -d" " -f2|sed /IMAGES/d|sed s/\"//)

# Get the configmap image list
cmlist=$(curl -sL "https://install.portworx.com/${pxver}/version?kbver=${kbver}" | sed "1,2d" | awk '{print $2}')

# Load all images with declarative repositories into the a variable. 
# These have 3 fields, i.e. registry/namespace/image
declared_list=$(echo "$aglist"| awk -F'/' 'NF==3')$'\n'
declared_list+=$(echo "$cmlist"| awk -F'/' 'NF==3')
# Load all images without declarative repositories into the a variable (i.e. undeclared default to docker.io)
# These have only 2 fields, i.e namespace/image, and container engines default back to docker.io as the registry.
# Patch them up for consistent declaration of the docker.io repository
#undeclared_list=$(echo "$aglist"| awk -F'/' 'NF==2' | awk '{print "docker.io/" $0}')$'\n'
#undeclared_list+=$(echo "$cmlist"| awk -F'/' 'NF==2'| awk '{print "docker.io/" $0}')
undeclared_list=$(echo "$aglist" | awk -F'/' 'NF==2 && $0 !~ /^registry\.k8s\.io/ {print "docker.io/" $0}')$'\n'
undeclared_list+=$(echo "$cmlist" | awk -F'/' 'NF==2 && $0 !~ /^registry\.k8s\.io/ {print "docker.io/" $0}')$'\n'
# Add lines starting with registry.k8s.io as-is
undeclared_list+=$(echo "$aglist" | awk -F'/' 'NF==2 && $0 ~ /^registry\.k8s\.io/')$'\n'
undeclared_list+=$(echo "$cmlist" | awk -F'/' 'NF==2 && $0 ~ /^registry\.k8s\.io/')

# concatenate the list
final_list="$declared_list"$'\n'
final_list+="$undeclared_list"


# Sort, and remove duplicates
echo "$final_list" | grep -v '^[[:space:]]*$' | sort | awk '!seen[$0]++'