#!/bin/bash
#TODO: also use pngout ?

echo "To kill the script, run"
echo "while true ;do ; killall optipng ; killall advpng ; killall pngcrush ; done"
echo "for a while"


cpucores=`getconf _NPROCESSORS_ONLN`


if [[ $(git rev-parse --is-inside-work-tree) != "true" ]] >& /dev/null ; then
	echo "fatal: Not a git repository!"
	echo "Make sure to be in a git repo!"
	echo "Exiting"
	exit 2
fi

echo "WARNING, this script is supposed to be run in a git repo"
echo "We will create a new branch now which the scriptwill work in."
git branch script/image_optim
git checkout script/image_optim
echo "Done"

timestartglobal()
{
	TSG=`date +%s.%N`
}

timeendglobal()
{
	TEG=`date +%s.%N`
	TDG=`calc $TEG - $TSG`
	echo "$TDG"
}

timestart()
{
	TS=`date +%s.%N`
}

timeend()
{
	TE=`date +%s.%N`
	TD=`calc $TE - $TS`
}


print()
{
	${VERBOSE} && echo $1
}

jpeg_remove_comment_and_exiv()
{
	print "Removing comments and exiv data from jpegs."
	timestart
	git ls-files ./ | grep -e "\.jpg$" -e "\.jpeg" | xargs -P ${cpucores} -n 1 jpegoptim --strip-all >> /tmp/image_optim_jpeg.log
	timeend
	print "$TD"
}

png_optimize_all()
{
	timestart
	print "starting to optimize pngs"
	git ls-files ./ | grep "\.png$" | xargs -P ${cpucores} -n 1 optipng -zc1-9 -zm1-9 -zs0-3 -f0-5  >> /tmp/mytrimage_png.log
	git ls-files ./ | grep "\.png$" | xargs -P ${cpucores} -n 1 advpng -z4 >> /tmp/mytrimage_png.log
	git ls-files ./ | grep "\.png$" | xargs -P ${cpucores} -n 1 -I '{}' pngcrush -rem gAMA -rem alla -rem cHRM -rem iCCP -rem sRGB -rem time {} {}.foo >> /tmp/mytrimage_png.log

	for i in $(git ls-files ./ | grep "\.png$") ; do
		if [[ `du -b $i | awk '{print $1}'` -gt `du -b $i.foo | awk '{print $1}'` ]] ; then
			mv $i.foo $i
		else
			rm $i.foo
		fi
	done
	timeend
	print "optimizing pngs took $TD"
}

VERBOSE=true
MAX_CORES=8
timestartglobal
jpeg_remove_comment_and_exiv
png_optimize_all
wait


git status | grep "modified" | awk '{print $3}' > /tmp/image_optim.todo #reprocess already changed images
todonr=`cat /tmp/image_optim.todo | wc -l`
echo $todonr todo
date=`date`
git commit -a -m "image_optim $date"

while [ $todonr -gt 0 ] ; do
	for i in $(cat /tmp/image_optim.todo | grep -e "\.jpg$" -e "\.jpeg") ; do
		timestart
		jpegoptim -f --strip-all $i >> /tmp/image_optim_jpeg.log
		timeend
		echo $TD $i
	done &



	for i in $(cat /tmp/image_optim.todo | grep "\.png$"); do  #png
		timestart
		optipng -zc1-9 -zm1-9 -zs0-3 -f0-5 $i >> /tmp/image_optim_png.log
		advpng -z4 $i >> /tmp/image_optim_png.log
		pngcrush -rem gAMA -rem alla -rem cHRM -rem iCCP -rem sRGB -rem time $i $i.foo  >> /tmp/image_optim_png.log
		#find out if we actually save some bytes or not
		if [[ `du -b $i | awk '{print $1}'` -gt `du -b $i.foo | awk '{print $1}'` ]] ; then
			mv $i.foo $i
		else
			rm $i.foo
		fi
		timeend
		echo $TD $i
	done &
	wait

git status | grep "modified" | awk '{print $3}' > /tmp/image_optim.todo
todonr=`cat /tmp/image_optim.todo | wc -l`
echo $todonr todo
date=`date`
git commit -a -m "image_optim $date"
done

timeendglobal
