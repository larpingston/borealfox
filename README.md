# borealfox, make firefox great again

## what it does?

hardened firefox settings with telemetry and data collection removed
forces https everywhere
routes dns thru mullvads adblocking resolver
installs ublock origin, vimium, localCDN and dark reader addons
disables the mozilla nonsense: pocket, firefox accounts, ai , etc
clean minimal userChrome.css

## installation

you need firefox and python installed on your system

```sh
git clone https://github.com/larpingston/borealfox
cd borealfox
./install.sh
```

it will set everything up and open a settings panel where you can configure borealfox

run `borealfox-settings` anytime to open the settings for borealfox

## uninstall

```sh
./uninstall.sh
```

wipes everything and goes back to firefox default state

## note

tested on arch and debian-based distros
