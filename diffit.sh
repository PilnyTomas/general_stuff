#!/bin/bash

# Initialize parameters
f_flag=0
d_flag=0
v_flag=0
path=""
base=""
compare=""

# List of extensions to be ignored by the vimdiff
IGNORE="':!*.o' ':!*.d' ':!*.cproject' ':!*proj*' ':!*.Identifier' ':!*identifier' ':!*.sdf' ':!*.sln' ':!*.log' ':!*.vbs'"

# Function to display help message
display_help() {
    echo "Usage: $(basename $0) -b bse_repo -c compare_repo [OPTIONS]"
    echo "Compare 2 repos"
    echo
    echo "  -f            Print list of changed files"
    echo "  -d            Print classic diff"
    echo "  -v            Use vimdiff"
    echo "  -p value      Path to file to be compared (style dependent on choice -d or -v (default -d). If both are chosen, -d will be first."
    echo "  -b value      (Mandatory) Base repository"
    echo "  -c value      (Mandatory) Compare againts the secondary repo"
    echo "  -h            Display this help and exit"
    echo
}

# Parse command line options.
while getopts fdvp:b:c:h OPTION
do
    case ${OPTION} in
        f) f_flag=1;;
        d) d_flag=1;;
        v) v_flag=1;;
        p) path=${OPTARG};;
        b) base=${OPTARG};;
        c) compare=${OPTARG};;
        h) display_help
           exit 0;;
        ?) display_help >&2
           exit 1;;
    esac
done

echo "Debug: f_flag=${f_flag}, d_flag=${d_flag}, v_flag=${v_flag}, path=\"${path}\", base=\"${base}\", compare=\"${compare}\", h=${h}"

# Check if mandatory parameters are set
if [ -z "$base" ] || [ -z "$compare" ]; then
    echo "Error: -b and -c are mandatory"
    display_help
    exit 1
fi

echo -e "Comparing \"$base\" to \"$compare\":\n\
- Print file list - $f_flag\n\
- Print classic diff - $d_flag\n\
- Start vimdiff - $v_flag\n\
- Compare filepath: \"$path\""

if [ ! -d "$base" ]; then
    echo "Error: base \"$base\" does nto exist!"
    exit 1
fi
if [ ! -d "$compare" ]; then
    echo "Error: compare \"$compare\" does nto exist!"
    exit 1
fi

cd $compare
echo "Debug: cd $compare"
echo "Debug: pwd: $(pwd)"

if [ $f_flag -eq 1 ]; then

    echo "Debug: file list"
    git --work-tree=../$base diff --name-only # list of changed files
fi

if [ ! -z $path ]; then
    echo "Debug: diff only filepath: \"$path\""
    if [ $v_flag -eq 1 ]; then
        vimdiff $path ../$base/$path
    else
        git diff $path ../$base/$path
    fi
else
    echo "Debug: diff entire repo"
    if [ $d_flag -eq 1 ]; then
        cd ..
        echo "Debug: clasic diff"
        #diff -r --exclude='*.o' $base $compare
        git diff --diff-filter=A --name-only $base $compare # get only new files
        #diff -r --exclude='*.o' --exclude='.git/objects' $base $compare
        #diff -r --exclude='*.o' $base $compare >> diff.txt
        #git --work-tree=../$base  diff # clasic diff - all on one page
        #git --work-tree=../$base --no-index diff # clasic diff - all on one page
    fi

    if [ $v_flag -eq 1 ]; then
        echo "Debug: vimdiff"
        git --work-tree=../$base difftool -w -- . $IGNORE  # open file-by-file side-by-side in vim
    fi
fi

cd ..
