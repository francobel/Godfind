#!/bin/zsh

domain=$1
subdomain_list=$2
shosubgo_api_key=""

mkdir -p subdomains/$domain
mkdir -p scanners/$domain

./dependencies/github-dorks.sh $domain

echo "Running amass on $domain"
amass enum -d $domain -o subdomains/$domain/amass.subdomains > /dev/null

echo "Running subfinder on $domain" 
subfinder -d $domain -o subdomains/$domain/subfinder.subdomains > /dev/null

echo "Running shosubgo on $domain"
./dependencies/shosubgo_linux_1_1 -d $domain -s $shosubgo_api_key

echo "Bruteforcing $domain with $subdomain_list"
shuffledns -d $domain -w $subdomain_list -o subdomains/$domain/shuffledns.subdomains -r dependencies/resolvers.txt

echo "Combining subdomain lists..."
cat subdomains/$domain/* | sort | uniq > subdomains/$domain/all.subdomains

echo "Finding out which sites are active"
python3 dependencies/probethis/probethis.py -f subdomains/$domain/all.subdomains -t 40 -o subdomains/$domain/active.subdomains

echo "Running active websites through Aquatone"
cat subdomains/$domain/all.subdomains | dependencies/aquatone > /dev/null

echo "Running nmap"
nmap -T4 -iL subdomains/$domain/all.subdomains -Pn --script http-title -o nmap --open

echo "Turning domains into IPs for masscan"
while read p; do
	dig +short $p | grep -E -o "([0-9]{1,3}[\.]){3}[0-9]{1,3}" \
	>> subdomains/$domain/full_list_of_IPs.txt
done < subdomains/$domain/all.subdomains
cat subdomains/$domain/full_list_of_IPs.txt | sort | uniq > subdomains/$domain/unique_IPs.txt

echo "Scanning top ports with masscan"
masscan --retries=5 --rate=50 -iL subdomains/$domain/unique_IPs.txt --top-ports 50>> scanners/$domain/masscan-results.txt

echo "Translating masscan results to something nmap can read"
python3 dependencies/mass2scan.py $domain

echo "Nmap scan with masscan results"
while read item;do
	nmap --append-output -oG scanners/$domain/nmap.gnmap $item;
done < scanners/$domain/nmap.txt

echo "Attempting to bruiteforce"
brutespray --file scanners/$domain/nmap.gnmap -t 5 -T 2

echo "Checking for subdomain takeover"
nuclei -l subdomains/$domain/active.subdomains -t takeovers -o nuclei.subdomain_takeover
nuclei -l subdomains/$domain/active.subdomains -t cves -o nuclei.cves
