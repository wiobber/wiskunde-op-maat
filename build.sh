#!/bin/bash

#: "${XAKE_IMAGE:=xake}"
: "${XAKE_IMAGE:=registry.gitlab.kuleuven.be/monitoraat-wet/xake:1.2.1a}"
: "${XAKE_IMAGE:=registry-ext.repo.icts.kuleuven.be/set/dsb/xake:1.2.1a}"
: "${MOUNTDIR:=$(pwd)}"

if [[ -f /.dockerenv ]]
then
    echo "Running in docker container ($HOSTNAME)"
elif [[ -n "$KUBERNETES_SERVICE_HOST" ]] 
then
    echo "Running in kubernetes container ($KUBERNETES_SERVICE_HOST)"
else 
    echo "Running $0 on host ($HOSTNAME)"

    if [[ "$1" == "-i" ]]
    then
        INTERACTIVE="-it"
    fi 

    if [[ "$LOCAL_IP" == "" ]]
    then
        LOCAL_IP=$(set -- $(hostname -I); echo "$1")
        echo "SETTING LOCAL_IP=$LOCAL_IP"
    fi
    echo "Restarting myself in docker container"	
    echo  docker run --env LOCAL_IP --env URL_XIMERA --env REPO_XIMERA --env GPG_KEY --env GPG_KEY_ID --network host --rm  $INTERACTIVE --mount type=bind,source=$MOUNTDIR,target=/code $XAKE_IMAGE ./build.sh $*
    docker run --env LOCAL_IP --env URL_XIMERA --env REPO_XIMERA --env GPG_KEY --env GPG_KEY_ID --network host --rm $INTERACTIVE --mount type=bind,source=$MOUNTDIR,target=/code $XAKE_IMAGE ./build.sh $*
    exit 0
    # END-OF-SCRIPT: this exec will never return !
fi

# We're for sure running in a container now

echo "Starting $*"

if [[ -f .ximera/ximera.4ht ]]; then
    echo "USING ximera.4ht from local repo"
    cp .ximera/ximera.4ht /root/texmf/tex/latex/ximeraLatex/
fi

if [[ -f .ximera/ximera.cls ]]; then
    echo "USING ximera.cls from local repo"
    cp .ximera/ximera.cls /root/texmf/tex/latex/ximeraLatex/
fi

if [[ -f .ximera/ximera.cfg ]]; then
    echo "USING ximera.cfg from local repo"
    cp .ximera/ximera.cfg /root/texmf/tex/latex/ximeraLatex/
fi

if [[ -f .ximera/xourse.cls ]]; then
    echo "USING xourse.cls from local repo"
    cp .ximera/xourse.cls /root/texmf/tex/latex/ximeraLatex/
fi
if [[ -f .ximera/xourse.4ht ]]; then
    echo "USING xourse.4ht from local repo"
    cp .ximera/xourse.4ht /root/texmf/tex/latex/ximeraLatex/
fi

if [[ -d .texmf ]]; then
    echo "USING .texmf etc from local repo"
    cp -r .texmf/* /usr/local/texlive/2019/texmf-dist/tex/generic/
fi


# Longer lines in pdflatex output
export max_print_line=1000
export error_line=254
export half_error_line=238

: "${LOCAL_IP:=localhost}"
: "${URL_XIMERA:=http://$LOCAL_IP:2000/}"     # default: publish to ximera-docker-instance, but 'localhost' does refer to THIS container
: "${REPO_XIMERA:=test}"
: "${NB_JOBS:=2}"
: "${XAKE:=xake}"
: "${DOCKER_MOUNT:=$(pwd)}"
while getopts ":hitd" opt; do
  case ${opt} in
    h ) 
       cat <<EOF
        Build and publish a ximera-repository to a ximera-server (via bake/frost/serve)

        Publishes to $URL_XIMERA$REPO_XIMERA 
EOF
       exit 0
      ;;
    i )
        echo "Interactive session"
        ;;
    d )
       XAKE="docker run --env GPG_KEY --env GPG_KEY_ID --network host --rm -it --mount type=bind,source=$(pwd),target=/code xake xake" 
       URL_XIMERA="http://$LOCAL_IP:2000/"
       echo "Using docker to run $XAKE  (from $DOCKER_MOUNT)"	

      ;;
    \? ) echo "Usage: build [-h] [-t]"
	 exit 1
      ;;
  esac
done
shift $((OPTIND -1))

COMMAND=$1

reset_file_times() {
 if find . -maxdepth 1 -name "*.tex" -mtime +1 | grep .
 then
  # .tex files older then 1 day: presumably the git was not checked out just now,
  # and modittimes are correct
  echo "Skipping resetting file times"
 else
  # all .tex files are recent, presumable just after a git clone. This would cause re-compile of everything
  # therefore: restore all modif-dates
  echo "Resetting file times"
  apt install git-restore-mtime    # should be in image !!!
  # git status   # in DETACHED HEAD in CI !!
  git restore-mtime -f
  ls -al *.tex *.sty *.pdf
 fi
}

if [[ "$COMMAND" == "bash" ]]
then
    ${XAKE%xake} /bin/bash
elif [[ "$COMMAND" == "bake" ]]
then
    # files with beamer are IGNORED by bake and bakePdf   (should only be complied to pdf, not html)
    #  do it 'by hand' here
    reset_file_times
    mkdir -p ximera-downloads
    echo "Compiling beamer and _pdf.tex files ..."
        find \( -name "*beamer*.tex" -o -name "*_pdf.tex" \) -printf '%P\n' | while read file; do
	ls -al ${file%tex}{tex,pdf,svg,log}
        if [[ "$file" -nt "${file/%.tex/.pdf}" ]]
        then
             echo "Compiling $file   (beamer)"
             $XAKE -v compilePdf $file
             echo "Copying $file to ximera-downloads"
             cp ${file/%.tex/.pdf} ximera-downloads
             echo "Converting $file to svg"
             pdf2svg ${file/%.tex/.pdf} ${file/%.tex/.svg}
        else
             echo "File $file uptodate"
        fi
    done
    echo "Baking other files ..."
    $XAKE  --skip-mathjax -v --jobs $NB_JOBS bake # Genereer de html files
elif [[ "$COMMAND" == "cleanstandaard" ]]
then
    NAME=standaard
    rm -rf ximera-downloads/"$NAME"_pdf
    find -name "*-$NAME.pdf" -printf '%P\n' | xargs -I{} sh -c 'echo "Removing $1"; rm "$1"' -- {} "$NAME" # remove .pdf's
elif [[ "$COMMAND" == "cleanhandout" ]]
then
    NAME=handout
    rm -rf ximera-downloads/"$NAME"_pdf
    find -name "*-$NAME.pdf" -printf '%P\n' | xargs -I{} sh -c 'echo "Removing $1"; rm "$1"' -- {} "$NAME" # remove .pdf's
elif [[ "$COMMAND" == "bakestandaard" ]]
then
    NAME=standaard
    reset_file_times
    $XAKE --jobs $NB_JOBS -v bakePdf "$NAME" 
    find -name "*-$NAME.pdf" -printf '%P\n' | xargs -I{} dirname ximera-downloads/"$NAME"_pdf/{} | xargs mkdir -p # create necessairy folders
    find -name "*-$NAME.pdf" -printf '%P\n' | xargs -I{} sh -c 'echo "Move $1 to ximera-downloads"; cp "$1" ximera-downloads/"$2"_pdf/"${1%-*}.pdf" || (echo "Failed moving" && exit 1)' -- {} "$NAME" # Copy to ximera-downloads
elif [[ "$COMMAND" == "bakehandout" ]]
then
    NAME=handout
    # files with _pdf are IGNORED by bake and bakePdf   (should only be complied to pdf, not html)
    #  do it 'by hand' here Needed to create the handouts including formularia
    reset_file_times
    mkdir -p ximera-downloads
    echo "Compiling _pdf.tex files ..."
        find \( -name "*_pdf.tex" \) -printf '%P\n' | while read file; do
	ls -al ${file%tex}{tex,pdf,log}
        if [[ "$file" -nt "${file/%.tex/.pdf}" ]]
        then
             echo "Compiling $file   (beamer)"
             $XAKE -v compilePdf $file
             cp ${file/%.tex/.pdf} ximera-downloads
             cp ${file/%.tex/.pdf} ${file/%_pdf.tex/-handout_pdf.pdf}
        else
             echo "File $file   uptodate (beamer)"
        fi
    done
    timeout 50m $XAKE -v --jobs $NB_JOBS bakePdf "$NAME" "\\PassOptionsToClass{handout}{ximera}\\PassOptionsToClass{handout}{xourse}"
    echo "Moving pdfs to ximera-downloads"
    find -name "*-$NAME.pdf" -printf '%P\n' | xargs -I{} dirname ximera-downloads/"$NAME"_pdf/{} | xargs mkdir -p # create necessairy folders
   #find -name "*-$NAME.pdf" -printf '%P\n' | xargs -I{} sh -c 'echo "Move $1 to ximera-downloads"; cp "$1" ximera-downloads/"$2"_pdf/"${1%-*}.pdf" || (echo "Failed moving" && exit 1)' -- {} "$NAME" # Copy to ximera-downloads
    find -name "*-$NAME.pdf" -printf '%P\n' | xargs -I{} sh -c 'cp "$1" ximera-downloads/"$2"_pdf/"${1%-*}.pdf" || (echo "Failed moving" && exit 1)' -- {} "$NAME" # Copy to ximera-downloads

elif [[ "$COMMAND" == "bakebeamer" ]]
then
    # files with beamer are IGNORED by bake ansd bakePdf   (should only be complied to pdf, not html)
    #  do it 'by hand' here
    NAME=handout
    reset_file_times
    echo "Compiling beamer files ..."
    find -name "*beamer*.tex" -printf '%P\n' |grep -v preamble | grep -v handout | while read file; do
	ls -al ${file%tex}{tex,pdf,log}
        if [[ "$file" -nt "${file/%.tex/.pdf}" ]]
        then
            echo "Compiling $file   (beamer)"
            $XAKE -v compilePdf $file
            $XAKE -v compilePdf $file  $NAME "\\PassOptionsToClass{handout}{beamer}"
        else
            echo "File $file   uptodate (beamer)"
        fi
        mkdir -p public
        basename=$(basename $file)
        cp ${file/%.tex/.pdf} public/${basename/%.tex/.pdf}
        cp ${file/%.tex/-handout.pdf} public/${basename/%.tex/-handout.pdf}
        mkdir -p $(dirname ximera-downloads/"$NAME"_pdf/$file})
        cp ${file/%.tex/.pdf} ximera-downloads/${NAME}_pdf/${file/%.tex/.pdf}
        cp ${file/%.tex/-handout.pdf} ximera-downloads/${NAME}_pdf/${file/%.tex/-handout.pdf}
    done
    echo "Compiling _pdf files ..."
    find -name "*_pdf.tex" -printf '%P\n' | while read file; do
	ls -al ${file%tex}{tex,pdf,log}
        #if [[ "$file" -nt "${file/%.tex/.pdf}" ]]
        #then
            echo "Compiling $file   (_pdf)"
            $XAKE -v compilePdf $file
        #else
        #    echo "File $file   uptodate (_pdf)"
        #fi
        mkdir -p public
        basename=$(basename $file)
        cp ${file/%.tex/.pdf} public/${basename/%.tex/.pdf}
        mkdir -p $(dirname ximera-downloads/"$NAME"_pdf/$file})
        cp ${file/%.tex/.pdf} ximera-downloads/${NAME}_pdf/${file/%.tex/.pdf}
    done
elif [[ "$COMMAND" == "serve" ]]
then
    echo "xake serve"
    if [[ -f "$GPG_KEY" ]]
    then
        cat $GPG_KEY | base64 --decode > .gpg # decode the base64 gpg key
    else 
        echo "$GPG_KEY" >.gpg # | base64 --decode > .gpg # decode the base64 gpg key
    fi
    echo "Importing key"
    gpg --import .gpg 
    rm .gpg # remove the gpg key so he is certainly not cached
    ### BRANCHPART=`echo "*$CI_BUILD_REF_NAME" | tr '[:upper:]' '[:lower:]'` # Add star and lowercase
    ### if [ "$MASTER_WITH_STAR" = 'false' ]; then REPO=$REPO_BASE""${BRANCHPART/*master/}; else REPO=$REPO_BASE""$BRANCHPART; fi
    echo "KEYSERVER gpg -v --keyserver $URL_XIMERA --send-key $GPG_KEY_ID"
    gpg -v --keyserver $URL_XIMERA --send-key "$GPG_KEY_ID"
    echo "xake NAME: $XAKE -U $URL_XIMERA -k $GPG_KEY_ID name $REPO_XIMERA"
    $XAKE -v -U $URL_XIMERA -k "$GPG_KEY_ID" name "$REPO_XIMERA" # Stel de repository in, op master is dit REPO_BASE, anders REPO_BASE*<branch>
#    echo "Prepare git repo"
#    git fetch --unshallow # Zorg ervoor dat we de hele geschiedenis hebben ipv enkel een deel, anders werkt het serven niet
#   .git config core.fileMode false
#    git branch -D master || true    #ignore error
#    git checkout -B master # doe alsof we op master zitten
    echo "xake FROST"
    $XAKE -v frost # Zorg voor juiste links etc = maak metadata.json en tag etc
    echo "xake SERVE"
	echo "git status:"
    git status
	echo "git tag -n"
    git tag -n
	echo "git rev-parse --abbrev-ref --all:"
    git rev-parse --abbrev-ref --all
	echo "git remote -v:"
	git remote -v
    $XAKE -v serve 2>&1 # Upload files = push tag
else
    echo "Pass to xake ..."
    xake $*
fi


#exit 0; % ignore errors
