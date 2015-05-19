# Create base container
sudo lxc-create -t ubuntu -n frontend
sudo lxc-start -n frontend
sudo lxc-attach -n frontend -- sudo apt-get install -y openjdk-7-jre
sudo lxc-stop -n frontend

# Clone other java dependent containers
sudo lxc-clone -o frontend -n authorisation
sudo lxc-clone -o frontend -n authentication
sudo lxc-clone -o frontend -n person
sudo lxc-clone -o frontend -n session

# Move application specific files into root file systems
sudo mkdir /var/lib/lxc/frontend/rootfs/frontend
sudo cp /host/volume-frontend/* /var/lib/lxc/frontend/rootfs/frontend

sudo mkdir /var/lib/lxc/authorisation/rootfs/authorisation
sudo cp /host/volume-authorisation/* /var/lib/lxc/authorisation/rootfs/authorisation

sudo mkdir /var/lib/lxc/authentication/rootfs/authentication
sudo cp /host/volume-authentication/* /var/lib/lxc/authentication/rootfs/authentication

sudo mkdir /var/lib/lxc/session/rootfs/session
sudo cp /host/volume-session/* /var/lib/lxc/session/rootfs/session

sudo mkdir /var/lib/lxc/person/rootfs/person
sudo cp /host/volume-person/* /var/lib/lxc/person/rootfs/person
source /host/image-nginx-lua/provision.sh

# Move upstart configuration files into the correct target directory
sudo cp /host/upstart/frontend.conf /var/lib/lxc/frontend/rootfs/etc/init
sudo cp /host/upstart/authorisation.conf /var/lib/lxc/authorisation/rootfs/etc/init
sudo cp /host/upstart/authentication.conf /var/lib/lxc/authentication/rootfs/etc/init
sudo cp /host/upstart/person.conf /var/lib/lxc/person/rootfs/etc/init
sudo cp /host/upstart/session.conf /var/lib/lxc/session/rootfs/etc/init

# Start up the containers
sudo lxc-start -n frontend
sudo lxc-start -n authorisation
sudo lxc-start -n authentication
sudo lxc-start -n session
sudo lxc-start -n person

# Network containers
# All containers should have a mapping to the web container
echo "$(sudo lxc-info -n web -iH) web" | sudo tee -a /var/lib/lxc/*/rootfs/etc/hosts

# The web container need to have a mapping to all other containers
echo "$(sudo lxc-info -n frontend -iH) frontend" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts
echo "$(sudo lxc-info -n authorisation -iH) authorisation" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts
echo "$(sudo lxc-info -n authentication -iH) authentication" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts
echo "$(sudo lxc-info -n person -iH) person" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts
echo "$(sudo lxc-info -n session -iH) session" | sudo tee -a /var/lib/lxc/web/rootfs/etc/hosts

# Set up firewall rule on host to forward port 80 to web container
sudo iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 80 -j DNAT --to $(sudo lxc-info -iH -n web):8080
