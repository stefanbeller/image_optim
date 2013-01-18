#!/bin/bash
#TODO: also use pngout ?

echo "To kill the script, run"
echo "while true ; do killall optipng ; killall advpng ; killall pngcrush ; done"
echo "for a while"

VERBOSE=true
cpucores=`getconf _NPROCESSORS_ONLN`

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

make_sure_we_are_safe()
{
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
}


git_commit()
{
	date=`date`
	git status
	git commit -a -m "image_optim $date"
	git commit --ammend --author="imageoptim"
}



jpeg_remove_comment_and_exiv()
{
	print "Removing comments and exiv data from jpegs."
	timestart
	git ls-files ./ | grep -e "\.jpg$" -e "\.jpeg" | xargs -P ${cpucores} -n 1 jpegoptim --strip-all >> /tmp/image_optim_jpeg.log
	timeend
	print "$TD"
}

filelist=`git ls-files ./ | grep "\.png$"`
png_optimize_all()
{
	if [ ! -z "${filelist}" ] ; then
		print "starting to optimize pngs"
		LOGFILE="/tmp/image_optim_png.log"

		while [ "${filelist}" != "" ] ; do
			numberoffiles=$(echo ${filelist} | wc -w)
			print "starting to optimize ${numberoffiles} pngs."
			timestart
			echo ${filelist} | xargs -P ${cpucores} -n 1 optipng  -zc1-9 -zm1-9 -zs0-3 -f0-5  |& grep "\ Processing" >> "${LOGFILE}" 
			echo ${filelist} | xargs -P ${cpucores} -n 1 advpng -z4 >> "${LOGFILE}"
			# we need to call xargs 2 times: the first time to separate the input strings,
			# the second time to have -I {} working to place the inputs name multiple time in the
			# output command
			echo ${filelist} | xargs -P 1 -n 1 | xargs -P ${cpucores} -n 1 -I '{}' pngcrush -rem gAMA -rem alla -rem cHRM -rem iCCP -rem sRGB -rem time {} {}.foo |& grep -v "\ |\ " >> "${LOGFILE}"

			# deciding for which file to use is easy for cpu,
			# waiting for i/o, no need to parallelize it.
			newfilelist=""
			for i in ${filelist} ; do
				if [[ `du -b $i | awk '{print $1}'` -gt `du -b $i.foo | awk '{print $1}'` ]] ; then
					mv $i.foo $i
					newfilelist="${newfilelist} $i"
				else
					rm $i.foo
				fi
			done
			filelist=${newfilelist}

			timeend
			print "a run optimizing pngs took $TD"
		done
		git_commit
		png_optimize_all
		filelist=`git log -1 --stat --pretty="%b" | sed '$d' | awk '{print $1}'
	fi
}

timestartglobal
make_sure_we_are_safe
jpeg_remove_comment_and_exiv
png_optimize_all
git_commit
timeendglobal
