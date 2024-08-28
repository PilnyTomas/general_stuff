#!/bin/bash

#DEBUG=true
debug_echo() {
    if [ "$DEBUG" = true ]; then
        echo -e "DEBUG: $1"
    fi
}

# Initialize parameters
o_flag=0
f_flag=0
n_flag=0
t_flag=0
s_flag=0
realtive=""
relative_modifier=""
d_flag=0
v_flag=0
diff_modifier="" # Complete strig with argument passed to the git diff command - automaticall compiled from the $modifier
modifier="" # Shortened param version
path=""
base=""
param_compare=""
default_report=0

# List of extensions to be ignored by the vimdiff
IGNORE="':!*.o' ':!*.d' ':!*.cproject' ':!*proj*' ':!*.Identifier' ':!*identifier' ':!*.sdf' ':!*.sln' ':!*.log' ':!*.vbs'"

# Function to display help message
display_help() {
    echo "Usage: $(basename $0) -b bse_repo -c compare_repo [OPTIONS]"
    echo "Compare repositories"
    echo
    echo "  -o            Print top-level overview of the changes - number of changed files and number of changed lines (if no other flag is specified this will be automatically set)"
    echo "  -f            Print list of changed files (cannot be combined with -n)"
    echo "  -n            Print list of new files (cannot be combined with -f)"
    echo "  -t            Print list of changed files in a tree style"
    echo "  -s            Modify the list or tree to show --stat"
    echo "  -r value      Add a relative path to compare the repos"
    echo "  -d            Print classic diff"
    echo "  -v            Use vimdiff"
    echo "  -m value      Git diff modifiers passed directly to \'--diff-filter\'. Most notable A-Added and M-Modified. For more info goto \'man git diff\' "
    echo "  -p value      Path to file to be compared (style dependent on choice -d or -v (default -d). If both are chosen, -d will be first."
    echo "  -b value      (Mandatory) Base repository"
    echo "  -c value      Compare againts the base repository (if not suplied the script will perfrom tests for all folders)"
    echo "  -h            Display this help and exit"
    echo "Note you might want to call \' git config --global core.autocrlf true\'"
}

# Parse command line options.
while getopts oftsr:dvm:p:b:c:h OPTION
do
    case ${OPTION} in
        o) o_flag=1;;
        f) f_flag=1;;
        n) f_flag=1;;
        t) t_flag=1;;
        s) s_flag=1;;
        r) relative=${OPTARG};;
        d) d_flag=1;;
        v) v_flag=1;;
        m) modifier=${OPTARG};;
        p) path=${OPTARG};;
        b) base=${OPTARG};;
        c) param_compare=${OPTARG};;
        h) display_help
           exit 0;;
        ?) display_help >&2
           exit 1;;
    esac
done

# Get the list of directories in the current working directory
if [ -z "$param_compare" ]; then
    directories=$(find . -maxdepth 1 -type d)
    debug_echo "Comparing \"$base\" to all repos in folder"
else
    directories="$param_compare"
    debug_echo "Comparing \"$base\" to \"$param_compare\":\n"
fi

debug_echo "o_flag=${o_flag}, f_flag=${f_flag}, n_flag=${n_flag}, t_flag=${t_flag}, s_flag=${s_flag}, d_flag=${d_flag}, modifier=${modifier}, v_flag=${v_flag}, path=\"${path}\", base=\"${base}\", param_compare=\"${param_compare}\", h=${h}"

# Check if mandatory parameters are set
if [ -z "$base" ]; then
    echo "Error: -b is mandatory"
    display_help
    exit 1
fi

if [ ! -d "$base" ]; then
    echo "Error: base \"$base\" does not exist!"
    exit 1
fi

if [ ! -z $relative ]; then
    relative_modifier="--relative=$relative"
    debug_echo "relative_modifier=$relative_modifier"
fi

if [ ! -z $modifier ]; then
    diff_modifier="--diff-filter=$modifier"
    debug_echo "modifier=\"$modifier\" => diff_modifier: \"$diff_modifier\""
else
    #diff_modifier="--name-only"
    diff_modifier=""
    debug_echo "modifier=\"$modifier\" => diff_modifier: \"$diff_modifier\""
fi

# if [ "$o_flag" = false ] && [ "$f_flag" = false ] && [ "$n_flag" = false ] && [ "$t_flag" = false ] && [ "$d_flag" = false ] && [ "$v_flag" = false ]; then
if [ "$o_flag" -eq 0 ] && [ "$f_flag" -eq 0 ] && [ "$n_flag" -eq 0 ] && [ "$t_flag" -eq 0 ] && [ "$d_flag" -eq 0 ] && [ "$v_flag" -eq 0 ]; then
    debug_echo "No flag was specified, set default_report to true and print the overview."
    default_report=1
else
    debug_echo "some of the flags was specified - do NOT set default_report."
fi



debug_echo "pwd: $(pwd)"

# Loop over each directory
for compare in $directories; do
    # Skip the current directory (.) and the base directory
    debug_echo "Check directory \"$compare\" ..."
    if [ "$compare" != "." ] && [ "$compare" != "./$base" ]; then

        if [ ! -d "$compare" ]; then
            echo "Error: Repo folder \"$compare\" does not exist!"
            exit 1
        fi
        debug_echo "OK - process it."

        cd $compare
        debug_echo "cd $compare"
        debug_echo "pwd: $(pwd)"

        if [ $default_report -eq 1 ]; then
            echo "Overview for $compare"

            # echo "New files:"
            # git --work-tree=../$base diff --stat --diff-filter=A  | tail -n 1 2> /dev/null # list of changed files
            # #if empty output then echo "None"

            # echo "Modified files:"
            # git --work-tree=../$base diff --stat --diff-filter=M  | tail -n 1 2> /dev/null # list of changed files
            # #if empty output then echo "None"

            # echo "Deleted files:"
            # git --work-tree=../$base diff --stat --diff-filter=D  | tail -n 1 2> /dev/null # list of changed files
            # #if empty output then echo "None"

            # echo "Total:"
            # git --work-tree=../$base diff --stat | tail -n 1 2> /dev/null # list of changed files
            # #if empty output then echo "None"

            # New files
            new_files=$(git --work-tree=../$base diff --stat --diff-filter=A | tail -n 1 2> /dev/null)
            echo -n "New files: "
            [ -z "$new_files" ] && echo "None" || echo "$new_files"

            # Modified files
            modified_files=$(git --work-tree=../$base diff --stat --diff-filter=M | tail -n 1 2> /dev/null)
            echo -n "Modified files: "
            [ -z "$modified_files" ] && echo "None" || echo "$modified_files"

            # Deleted files
            deleted_files=$(git --work-tree=../$base diff --stat --diff-filter=D | tail -n 1 2> /dev/null)
            echo -n "Deleted files: "
            [ -z "$deleted_files" ] && echo "None" || echo "$deleted_files"

            # Total
            total_files=$(git --work-tree=../$base diff --stat | tail -n 1 2> /dev/null)
            echo -n "Total: "
            [ -z "$total_files" ] && echo "None" || echo "$total_files"
        fi


        if [ $o_flag -eq 1 ]; then
            debug_echo "overview"
            git --work-tree=../$base diff --stat $diff_modifier $relative_modifier | tail -n 1 2> /dev/null # list of changed files
        fi

        if [ $f_flag -eq 1 ]; then
            debug_echo "file list"
            if [ $s_flag -eq 0 ]; then
                #debug_echo " - name only"
                git --work-tree=../$base diff --name-only $diff_modifier $relative_modifier 2> /dev/null # list of changed files
            else
                #debug_echo " - stat"
                #debug_echo "git --work-tree=../$base diff --stat $diff_modifier $relative_modifier 2> /dev/null" # list of changed files with stats
                git --work-tree=../$base diff --stat $diff_modifier $relative_modifier 2> /dev/null # list of changed files with stats
            fi
        fi

        if [ $t_flag -eq 1 ]; then
            #debug_echo "tree-style file list"
            if [ $s_flag -eq 0 ]; then
                git --work-tree=../$base diff --name-only $diff_modifier $relative_modifier 2> /dev/null | grep -v "warning:" | tree --fromfile
            else
                git --work-tree=../$base diff --stat $diff_modifier 2> /dev/null | grep -v "warning:" | tree --fromfile
            fi
        fi

        #if [ $v_flag -eq 1 || $d_flag -eq 1 && ! -z $path ]; then
        if  [ $v_flag -eq 1 ] || [ $d_flag -eq 1 ] && [ -n "$path" ]; then
            debug_echo "diff only filepath. base= \"../$base/$path\" compare \"$path\""
            if [ $v_flag -eq 1 ]; then
                if [ ! -z $relative ]; then
                    vimdiff ../$base/$path $relative/$path
                else
                    vimdiff ../$base/$path $path
                fi
            else
                if [ ! -z $relative ]; then
                    git diff ../$base/$path $relative/$path
                else
                    git diff ../$base/$path $path
                fi
            fi
        elif [ $v_flag -eq 1 ] || [ $d_flag -eq 1 ]; then
            debug_echo "file path not given"
            if [ $d_flag -eq 1 ]; then
                #cd ..
                debug_echo "clasic diff"
                #git --work-tree=../$base diff $relative_modifier # clasic diff - all on one page
                #git --work-tree=../$base diff --no-index $diff_modifier $relative_modifier # clasic diff - all on one page
                #debug_echo "pwd=$(pwd)"
                #debug_echo "git --work-tree=../$base diff $diff_modifier $relative_modifier"
                #git --work-tree=../$base diff $diff_modifier $relative_modifier #2> /dev/null

                debug_echo "git diff --no-index ../$base ./$realtive"
                git diff --no-index ../$base ./$realtive
            fi

            if [ $v_flag -eq 1 ]; then
                debug_echo "vimdiff"
                git --work-tree=../$base difftool -w -- . $IGNORE  # open file-by-file side-by-side in vim
            fi
        fi

        cd ..

    fi
done


exit 0

# Setup - add remote repo containgin the -00 version (sanitized build) and name it simply '0'
git remote add -f 0 git@github.com:jdkvision/FW-Hx4119-00.git

# List with statistics
mkdir ../logs
git diff --stat=200 0/main  --diff-filter=M > ../logs/mod_stat.list
tree --fromfile ../logs/mod_stat.list > ../logs/mod_stat.tree

git diff --stat=200 0/main --diff-filter=A > ../logs/add_stat.list
tree --fromfile ../logs/add_stat.list > ../logs/add_stat.tree

git diff --stat=200 0/main > ../logs/all_stat.list
tree --fromfile ../logs/all_stat.list > ../logs/all_stat.tree

# List without statistics
git diff 0/main --name-only --diff-filter=M > ../logs/mod.list
tree --fromfile ../logs/mod.list > ../logs/mod.tree

git diff 0/main --name-only --diff-filter=A > ../logs/add.list
tree --fromfile ../logs/add.list > ../logs/add.tree

git diff 0/main --name-only > ../logs/all.list
tree --fromfile ../logs/all.list > ../logs/all.tree
tree --fromfile ../logs/mod_stat.list > ../logs/mod_stat.tree
tree --fromfile ../logs/add_stat.list > ../logs/add_stat.tree
tree --fromfile ../logs/all_stat.list > ../logs/all_stat.tree
tree --fromfile ../logs/mod.list > ../logs/mod.tree
tree --fromfile ../logs/add.list > ../logs/add.tree
tree --fromfile ../logs/all.list > ../logs/all.tree