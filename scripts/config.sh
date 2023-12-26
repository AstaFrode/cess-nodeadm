#!/bin/bash

source /opt/cess/nodeadm/scripts/utils.sh

mode=$(yq eval ".node.mode" $config_file)
if [ $? -ne 0 ]; then
    log_err "the config file: $config_file may be invalid, please reconfig again"
    exit 1
fi

readonly local_chain_ws_url="ws://127.0.0.1:9944"
readonly host_docker_chain_ws_url="ws://cess-chain:9944"
default_chain_ws_url=$local_chain_ws_url

function reset_default_chain_url_by_mode() {
    if [ x"$mode" == x"authority" ]; then
        default_chain_ws_url=$host_docker_chain_ws_url
    else
        default_chain_ws_url=$local_chain_ws_url
    fi
}
reset_default_chain_url_by_mode

config_help() {
    cat <<EOF
cess config usage:
    help                    show help information
    show                    show configurations
    set                     set and generate new configurations, then try pull corresponding images
    generate                generate new configurations
    pull-image              download corresponding images after set config
    chain-port {port}       set chain port and generate new configuration, default is 30336
    conn-chain {ws}         set conneted chain ws and generate new configuration, default is $default_chain_ws_url
EOF
}

config_show() {
    local keys=
    if [[ $mode = "authority" ]]; then
        keys=('"node"' '"chain"' '"kaleido"')
    elif [[ $mode = "storage" ]]; then
        keys=('"node"' '"chain"' '"bucket"')
    elif [[ $mode = "watcher" ]]; then
        keys=('"node"' '"chain"')
    fi
    local ss=$(join_by , ${keys[@]})
    yq eval ". |= pick([$ss])" $config_file -o json
}

set_chain_name() {
    local -r default="cess-node"
    local to_set=""
    local current="$(yq eval ".chain.name" $config_file)"
    if [ x"$current" != x"" ]; then
        read -p "Enter cess node name (current: $current, press enter to skip): " to_set
    else
        read -p "Enter cess node name (default: $default): " to_set
    fi
    to_set=$(echo "$to_set")
    if [ x"$to_set" != x"" ]; then
        local rn=$(rand 100000 999999)
        yq -i eval ".chain.name=\"$to_set-$rn\"" $config_file
    elif [ x"$current" == x"" ]; then
        local rn=$(rand 100000 999999)
        yq -i eval ".chain.name=\"$default-$rn\"" $config_file
    fi
}

function is_sgx_satisfied() {
    get_distro_name
    if [ $? -ne 0 ]; then
        exit 1
    fi
    if [ x"$DISTRO" != x"Ubuntu" ]; then
        log_err "Current only support Ubuntu and the kernel version must be greater than 5.11 on authority mode"
        return 1
    fi
    local kernal_version=$(uname -r | cut -d . -f 1,2)
    if is_ver_a_ge_b 5.11 $kernal_version; then
        log_err "The kernel version must be greater than 5.11, your version is $kernal_version. Please upgrade the kernel first."
        return 1
    fi
    # install and run sgx_enable program
    if install_sgx_enable_if_absent; then
        sgx_enable
    else
        exit 1
    fi
    return $?
}

set_node_mode() {
    local -r default="authority"
    local to_set=""
    local current=$mode
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Select node mode from 'authority | storage | watcher' (current: $current, press enter to skip): " to_set
        else
            read -p "Select node mode from 'authority | storage | watcher' (default: $default): " to_set
        fi
        to_set=$(echo "$to_set")
        if [ x"$to_set" != x"" ]; then
            if [ x"$to_set" == x"authority" ]; then
                if ! is_sgx_satisfied; then
                    continue
                fi
            fi
            if [ x"$to_set" == x"authority" ] || [ x"$to_set" == x"storage" ] || [ x"$to_set" == x"watcher" ]; then
                if [ x"$to_set" != x"$mode" ]; then
                    mode=$to_set
                    yq -i eval ".node.mode=\"$to_set\"" $config_file
                fi
                break
            else
                log_err "Input error, please input 'authority' 'storage' or 'watcher'"
                continue
            fi
        elif [ x"$current" == x"" ]; then
            mode=$default
            yq -i eval ".node.mode=\"$default\"" $config_file
            break
        fi
        break
    done
    local path_with_mode="/opt/cess/$mode/"
    if [ ! -d path_with_mode ]; then
        mkdir -p $path_with_mode
    fi
}

set_external_ip() {
    local ip=""
    local current="$(yq eval ".node.externalIp" $config_file)"
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Enter external ip for the machine (current: $current, press enter to skip): " ip
        else
            read -p "Enter external ip for the machine: " ip
        fi
        ip=$(echo "$ip")
        if [ x"$ip" != x"" ]; then
            yq -i eval ".node.externalIp=\"$ip\"" $config_file
            break
        elif [ x"$current" != x"" ]; then
            break
        fi
    done
}

set_domain_name() {
    local to_set=""
    local current="$(yq eval ".node.domainName" $config_file)"
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Enter a domain name for the machine (current: $current, press enter to skip): " to_set
        else
            read -p "Enter a domain name for the machine: " to_set
        fi
        to_set=$(echo "$to_set")
        if [ x"$to_set" != x"" ]; then
            yq -i eval ".node.domainName=\"$to_set\"" $config_file
            break
        elif [ x"$current" != x"" ]; then
            break
        fi
    done
}

set_chain_ws_url() {
    local -r default=$default_chain_ws_url
    local to_set=""
    local current="$(yq eval ".node.chainWsUrl //\"\"" $config_file)"
    if [ x"$current" == x"$local_chain_ws_url" ] || [ x"$current" == x"$host_docker_chain_ws_url" ]; then
        current=""
    fi
    if [ x"$current" != x"" ]; then
        read -p "Enter cess chain ws url (current: $current, press enter to skip): " to_set
    else
        read -p "Enter cess chain ws url (default: $default): " to_set
    fi
    to_set=$(echo "$to_set")
    if [ x"$to_set" != x"" ]; then
        yq -i eval ".node.chainWsUrl=\"$to_set\"" $config_file
    elif [ x"$current" == x"" ]; then
        yq -i eval ".node.chainWsUrl=\"$default\"" $config_file
    fi
}

function assign_chain_ws_url_to_local() {
    yq -i eval ".node.chainWsUrl=\"$local_chain_ws_url\"" $config_file
}

function assign_backup_chain_ws_urls_by_profile() {
    local chain_urls=
    if [[ $profile = "testnet" ]]; then
        chain_urls=(
            "wss://testnet-rpc0.cess.cloud/ws/"
            "wss://testnet-rpc1.cess.cloud/ws/"
        )
    elif [[ $profile = "devnet" ]]; then
        chain_urls=(
            "wss://devnet-rpc.cess.cloud/ws-1/"
            "wss://devnet-rpc.cess.cloud/ws/"
            "wss://devnet-rpc.cess.cloud/ws-3/"
        )
    fi
    if [[ -n $chain_urls ]]; then
        local quoted=()
        for ix in ${!chain_urls[*]}; do
            quoted+=(\"${chain_urls[$ix]}\")
        done
        local ss=$(join_by , ${quoted[@]})
        yq -i eval ".node.backupChainWsUrls=[$ss]" $config_file
    fi
}

set_kaleido_stash_account() {
    local stash_acc=""
    local current="$(yq eval ".kaleido.stashAccount" $config_file)"
    read -p "Enter cess validator stash account (current: $current, press enter to skip): " stash_acc
    if [ x"$stash_acc" == x"" ]; then
        stash_acc=$(echo "$current")
    fi
    if [ x"$stash_acc" != x"null" ]; then
        yq -i eval ".kaleido.stashAccount=\"$stash_acc\"" $config_file
    else
        stash_acc=""
    fi
    echo "$stash_acc"
}

set_tee_type() {
    local tee_type=""
    while true; do
        if [ x"$1" == x"" ];then
            # read -p "Enter what kind of tee worker would you want to be [Certifier/Marker]: " tee_type
            # if [ x"$tee_type" != x"Certifier" ] && [ x"$tee_type" != x"Marker" ];then
            #     echo "Please enter 'Certifier' or 'Marker'!"
            #     continue
            # fi
            echo -e "\033[33mYour Tee worker will work as 'Marker'!\033[0m"
            tee_type="Marker"
        else
            read -p "Enter what kind of tee worker would you want to be [Full/Verifier]: " tee_type
            if [ x"$tee_type" != x"Full" ] && [ x"$tee_type" != x"Verifier" ];then
                echo "Please enter 'Full' or 'Verifier'!"
                continue
            fi
        fi
        tee_type=$(echo "$tee_type")
        if [ x"$tee_type" != x"" ]; then
            yq -i eval ".kaleido.teeType=\"$tee_type\"" $config_file
            break
        fi
    done
}

set_kaleido_ctrl_phrase() {
    local to_set=""
    local current="$(yq eval ".kaleido.controllerPhrase" $config_file)"
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Enter cess validator controller phrase (current: $current, press enter to skip): " to_set
        else
            read -p "Enter cess validator controller phrase: " to_set
        fi
        to_set=$(echo "$to_set")
        if [ x"$to_set" != x"" ]; then
            yq -i eval ".kaleido.controllerPhrase=\"$to_set\"" $config_file
            break
        elif [ x"$current" != x"" ]; then
            break
        fi
    done
}

function set_kaleido_port() {
    local to_set=""
    local current="$(yq eval ".kaleido.apiPort //10010" $config_file)"
    read -p "Enter listener port for kaleido (current: $current, press enter to skip): " to_set
    if [[ -z $to_set ]]; then
        return 0
    fi
    while true; do
        if is_uint $to_set && (($to_set <= 65535)); then
            yq -i eval ".kaleido.apiPort=$to_set" $config_file
            break
        fi
        read -p "  Please input a valid port number (press enter to skip): " to_set
        if [[ -z $to_set ]]; then
            break
        fi
    done
}

function set_kaleido_endpoint() {
    local current="$(yq eval ".kaleido.kldrEndpoint //\"\"" $config_file)"
    local input_uri=
    local extIp=$(http_proxy= curl -fsSL ifconfig.net)
    if [[ -z $current ]]; then
        echo "Start configuring the endpoint to access kaleido from the Internet"
        echo "  Try to get your external IP ..."
        local kldPort="$(yq eval ".kaleido.apiPort //10010" $config_file)"
        current="http://$extIp:$kldPort"
    fi
    read -p "Enter the kaleido endpoint (current: $current, press enter to skip): " input_uri
    if [[ -z $input_uri ]]; then
        input_uri=$(echo "$current")
    fi
    yq -i eval ".kaleido.kldrEndpoint=\"$input_uri\"" $config_file
    if [[ $input_uri =~ ^(http|https)://[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(/.*)?$ ]]; then
        local set_reverse_proxy=""
        read -p "Do you need to configure a domain name proxy with one click? (y/n): " set_reverse_proxy
        if [[ $set_reverse_proxy =~ ^[yY](es)?$ ]]; then
            yq -i eval ".nginx.confPath=\"/opt/cess/authority/proxy/conf\"" $config_file
            yq -i eval ".nginx.logPath=\"/opt/cess/authority/proxy/log\"" $config_file
            cleaned_head=$(echo "$input_uri" | sed 's|^http://||; s|^https://||' | sed 's|/$||')
            sed -i "s/\(server_name\s*\).*;/\1$cleaned_head;/" /opt/cess/nodeadm/tee.conf
        fi
    elif [[ $input_uri =~ ^(http|https)://[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:([0-9]+)$ ]]; then
        ##do nothing
        :
    else
        echo "Error: Invalid URI provided."
        exit 1
    fi
}

function assign_kaleido_podr2_max_threads() {
    local n=$(your_cpu_core_number)
    yq -i eval ".kaleido.podr2MaxThreads=\"$n\"" $config_file
}

set_bucket_income_account() {
    local to_set=""
    local current="$(yq eval ".bucket.incomeAccount" $config_file)"
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Input the earnings account (current: $current, press enter to skip): " to_set
        else
            read -p "Input the earnings account: " to_set
        fi
        to_set=$(echo "$to_set")
        if [ x"$to_set" != x"" ]; then
            yq -i eval ".bucket.incomeAccount=\"$to_set\"" $config_file
            break
        elif [ x"$current" != x"" ]; then
            break
        fi
    done
}

set_bucket_sign_phrase() {
    local to_set=""
    local current="$(yq eval ".bucket.signPhrase" $config_file)"
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Input the signature account mnemonic (current: $current, press enter to skip): " to_set
        else
            read -p "Input the signature account mnemonic: " to_set
        fi
        to_set=$(echo "$to_set")
        if [ x"$to_set" != x"" ]; then
            yq -i eval ".bucket.signPhrase=\"$to_set\"" $config_file
            break
        elif [ x"$current" != x"" ]; then
            break
        fi
    done
}

set_bucket_disk_path() {
    local -r default="/opt/cess/storage/disk"
    local to_set=""
    local current="$(yq eval ".bucket.diskPath" $config_file)"
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Input the workspace path (current: $current, press enter to skip): " to_set
        else
            read -p "Input the workspace path (default: $default): " to_set
        fi
        to_set=$(echo "$to_set")
        local to_update_path=
        if [ x"$to_set" != x"" ]; then
            to_update_path=$to_set
        elif [ x"$current" == x"" ]; then
            to_update_path=$default
        fi
        if [[ -z $to_update_path ]]; then
            break
        elif [[ ! -e $to_update_path ]]; then
            local need_create=
            read -p "The directory: $to_update_path does not exist, do you need to create it for you? (y/n) " need_create
            if [[ $need_create =~ ^[yY](es)?$ ]]; then
                mkdir -p $to_update_path
                if [[ $? -eq 0 ]]; then
                    yq -i eval ".bucket.diskPath=\"$to_update_path\"" $config_file
                    break
                fi
            fi
            continue
        elif [[ ! -d $to_update_path ]]; then
            log_err "The path: $to_update_path is not a directory"
            continue
        else
            yq -i eval ".bucket.diskPath=\"$to_update_path\"" $config_file
            break
        fi
    done
}

set_bucket_disk_spase() {
    local to_set=""
    local current="$(yq eval ".bucket.space" $config_file)"
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Input maximum usage space in GiB (current: $current, press enter to skip): " to_set
        else
            read -p "Input maximum usage space in GiB: " to_set
        fi
        to_set=$(echo "$to_set")
        if [ x"$to_set" != x"" ]; then
            yq -i eval ".bucket.space=$to_set" $config_file
            break
        elif [ x"$current" != x"" ]; then
            break
        fi
    done
}

set_bucket_port() {
    local to_set=""
    local current="$(yq eval ".bucket.port" $config_file)"
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Input the listening port (current: $current, press enter to skip): " to_set
        else
            read -p "Input the listening port: " to_set
        fi
        to_set=$(echo "$to_set")
        if [ x"$to_set" != x"" ]; then
            if check_port $to_set; then
                yq -i eval ".bucket.port=$to_set" $config_file
                break
            fi
        elif [ x"$current" != x"" ]; then
            break
        fi
    done
}

function set_bucket_use_cpu_cores() {
    local cpu_core_number=$(your_cpu_core_number)
    local to_set=""
    local current="$(yq eval ".bucket.useCpuCores //0" $config_file)"
    while true; do
        echo "Input the number of CPU cores used for mining; Your total CPU cores are ${cpu_core_number}"
        read -p "  (current: $current, 0 means all cores are used; press enter to skip): " to_set
        if [[ -z "$to_set" ]]; then
            break
        fi
        expr ${to_set} + 0 >/dev/null 2>&1
        if [[ $? -eq 0 && $to_set -ge 0 && $to_set -le ${cpu_core_number} || "$to_set" = "0" ]]; then
            yq -i eval ".bucket.useCpuCores=$to_set" $config_file
            break
        else
            log_err "Please enter an integer between 0 and ${cpu_core_number}. Your input is incorrect. Please re-enter!"
        fi
    done
}

function set_bucket_staking_account() {
    local to_set=
    local current="$(yq eval ".bucket.stakerAccount //\"\"" $config_file)"
    if [[ "$current" != "" ]]; then
        read -p "Input your staking account, if any (current: $current, press enter to skip): " to_set
    else
        read -p "Input your staking account, if any (press enter to skip): " to_set
    fi
    to_set=$(echo "$to_set")
    if [[ "$to_set" != "" ]]; then
        yq -i eval ".bucket.stakerAccount=\"$to_set\"" $config_file
    fi
}

function set_bucket_reserved_tws() {
    local to_set=
    local current="$(yq eval ".bucket.reservedTws //[] | join(\",\")" $config_file)"
    if [[ "$current" != "" ]]; then
        read -p "Input TEE addresses for priority use (current: $current, separate multiple values with commas, press enter to skip): " to_set
    else
        read -p "Input TEE addresses for priority use (separate multiple values with commas, press enter to skip): " to_set
    fi
    to_set=$(echo "$to_set")
    if [[ "$to_set" != "" ]]; then
        to_set=\"$(echo $to_set | sed 's/,/","/g')\"
        yq -i eval ".bucket.reservedTws=[$to_set]" $config_file
    fi
}

function set_chain_pruning_mode() {
    local -r default="8000"
    local to_set=""
    local current="$(yq eval ".chain.pruning" $config_file)"
    while true; do
        if [ x"$current" != x"" ]; then
            read -p "Enter cess chain pruning mode, 'archive' or number (current: $current, press enter to skip): " to_set
        else
            read -p "Enter cess chain pruning mode, 'archive' or number (default: $default): " to_set
        fi
        to_set=$(echo "$to_set")
        if [ x"$to_set" != x"" ]; then
            if [ x"$to_set" != x"archive" ]; then
                if [ -n "$to_set" ] && [ "$to_set" -eq "$to_set" ] 2>/dev/null; then
                    if [ $(("$to_set")) -lt 256 ]; then
                        log_err "the pruning mode must greater than 255 when as a number"
                        continue
                    fi
                else
                    log_err "the pruning mode must be 'archive' or greater than 255 when as a number"
                    continue
                fi
            fi
            yq -i eval ".chain.pruning=\"$to_set\"" $config_file
            break
        elif [ x"$current" == x"" ]; then
            yq -i eval ".chain.pruning=\"$default\"" $config_file
            break
        fi
        break
    done
}

function set_allow_log_collection() {
    local current="$(yq eval ".kaleido.allowLogCollection" $config_file)"
    if [[ "$current" = true ]]; then
        return
    fi
    local to_set=""
    read -p "❤️  Help us improve TEE Worker with anonymous crash reports & basic usage data? (y/n) : " to_set
    if [[ $to_set =~ ^[yY](es)?$ ]]; then
        yq -i eval ".kaleido.allowLogCollection=true" $config_file
    else
        yq -i eval ".kaleido.allowLogCollection=false" $config_file
    fi
}

function try_pull_image() {
    local img_name=$1
    local img_tag=$2

    local org_name="cesslab"
    if [ x"$region" == x"cn" ]; then
        org_name=$aliyun_address/$org_name
    fi
    if [ -z $img_tag ]; then
        img_tag="$profile"
    fi
    local img_id="$org_name/$img_name:$img_tag"
    log_info "download image: $img_id"
    docker pull $img_id
    if [ $? -ne 0 ]; then
        log_err "download image $img_id failed, try again later"
        exit 1
    fi
    return 0
}

function pull_images_by_mode() {
    log_info "try pull images, node mode: $mode"
    if [ x"$mode" == x"authority" ]; then
        try_pull_image cess-chain
        try_pull_image kaleido
        try_pull_image kaleido-rotator
    elif [ x"$mode" == x"storage" ]; then
        try_pull_image cess-chain
        try_pull_image cess-bucket
    elif [ x"$mode" == x"watcher" ]; then
        try_pull_image cess-chain
    else
        log_err "the node mode is invalid, please config again"
        return 1
    fi
    log_info "pull images finished"
    return 0
}

function assign_bucket_boot_addrs() {
    local boot_domain="boot-bucket-$profile.cess.cloud"
    local boot_addr="_dnsaddr.$boot_domain"
    if [ x"$mode" == x"storage" ]; then
        yq -i eval ".bucket.bootAddr=\"$boot_addr\"" $config_file
        return 0
    fi
    return 1
}

function config_set_all() {
    ensure_root

    local prev_mode=$mode

    set_node_mode

    if [ x"$mode" == x"authority" ]; then
        set_chain_name
        set_chain_ws_url
        set_kaleido_port
        set_kaleido_endpoint
        set_tee_type "$(set_kaleido_stash_account)"
        set_kaleido_ctrl_phrase
        set_allow_log_collection
        assign_kaleido_podr2_max_threads
    elif [ x"$mode" == x"storage" ]; then
        set_bucket_port
        set_bucket_income_account
        set_bucket_sign_phrase
        set_bucket_disk_path
        set_bucket_disk_spase
        set_bucket_use_cpu_cores
        set_bucket_staking_account
        set_bucket_reserved_tws
    elif [ x"$mode" == x"watcher" ]; then
        set_chain_name
        set_chain_pruning_mode
    else
        log_err "Invalid mode value: $mode"
        exit 1
    fi
    log_success "Set configurations successfully"

    if test -f "$compose_yaml"; then
        if [[ $prev_mode != $mode ]]; then
            log_info "the mode changed, remove all services for $prev_mode mode"
            docker compose -f $compose_yaml down
        fi
    fi

    # Generate configurations
    config_generate $@

    # Pull images
    pull_images_by_mode
}

config_conn_chain() {
    if [ x"$1" = x"" ]; then
        log_err "Please give connceted chain ws."
        config_help
        return 1
    fi
    yq -i eval ".node.chainWsUrl=\"$1\"" $config_file
    log_success "Set connected chain ws '$1' successfully"

    shift
    config_generate $@
}

config_chain_port() {
    if [ x"$1" = x"" ]; then
        log_err "Please give right chain port."
        config_help
        return 1
    fi
    yq -i eval ".chain.port=$1" $config_file
    log_success "Set chain port '$1' successfully"
    shift
    config_generate $@
}

function install_sgx_enable_if_absent() {
    log_info "Begin install sgx_enable ..."
    local sgx_enable_bin=/usr/local/bin/sgx_enable
    if [ -x $sgx_enable_bin ]; then
        return 0
    fi
    if ! command_exists gcc; then
        apt-get install -y gcc
    fi
    if ! command_exists make; then
        apt-get install -y make
    fi
    apt-get install -y

    local sgx_enable_src=$base_dir/sgx-software-enable/
    if make -s -C $sgx_enable_src; then
        mv $sgx_enable_src/sgx_enable $sgx_enable_bin
        chmod +x $sgx_enable_bin
        make -s -C $sgx_enable_src clean
        log_success "sgx_enable install successful"
        return 0
    fi
    log_err "Install sgx_enable failed"
    return 1
}

config_generate() {
    local cg_image="cesslab/config-gen:$profile"
    while getopts ":p" opt; do
        case ${opt} in
        p)
            docker pull $cg_image
            ;;
        esac
    done

    if [ ! -f "$config_file" ]; then
        log_err "config.yaml doesn't exists!"
        exit 1
    fi

    if [[ $mode = "storage" ]]; then
        assign_bucket_boot_addrs
        assign_chain_ws_url_to_local
        assign_backup_chain_ws_urls_by_profile
    elif [[ $mode = "watcher" ]]; then
        assign_chain_ws_url_to_local
    fi

    log_info "Start generate configurations and docker compose file"

    rm -rf $build_dir
    mkdir -p $build_dir/.tmp

    local cidfile=$(mktemp)
    rm $cidfile

    docker run --cidfile $cidfile -v $base_dir/etc:/opt/app/etc -v $build_dir/.tmp:/opt/app/.tmp -v $config_file:/opt/app/config.yaml $cg_image
    local res="$?"
    local cid=$(cat $cidfile)
    docker rm $cid

    if [ "$res" -ne "0" ]; then
        log_err "Failed to generate application configs, please check your config.yaml"
        exit 1
    fi

    cp -r $build_dir/.tmp/* $build_dir/
    rm -rf $build_dir/.tmp
    local base_mode_path=/opt/cess/$mode
    if [ x"$mode" == x"authority" ]; then
        if [ ! -d $base_mode_path/chain/ ]; then
            mkdir -p $base_mode_path/chain/
        fi
        cp $build_dir/chain/* $base_mode_path/chain/
        rm -rf $base_mode_path/proxy
        mkdir -p $base_mode_path/proxy/log $base_mode_path/proxy/conf
        cp /opt/cess/nodeadm/tee.conf $base_mode_path/proxy/conf/
    elif [ x"$mode" == x"storage" ]; then
        if [ ! -d $base_mode_path/chain/ ]; then
            mkdir -p $base_mode_path/chain/
        fi
        cp $build_dir/chain/* $base_mode_path/chain/

        if [ ! -d $base_mode_path/bucket/ ]; then
            mkdir -p $base_mode_path/bucket/
        fi
        cp $build_dir/bucket/* $base_mode_path/bucket/
    elif [ x"$mode" == x"watcher" ]; then
        if [ ! -d $base_mode_path/chain/ ]; then
            mkdir -p $base_mode_path/chain/
        fi
        cp $build_dir/chain/* $base_mode_path/chain/
    else
        log_err "Invalid mode value: $mode"
        exit 1
    fi
    chown -R root:root $build_dir
    #chmod -R 0600 $build_dir
    #chmod 0600 $config_file

    log_success "Configurations generated at: $build_dir"
}

config() {
    case "$1" in
    show)
        config_show
        ;;
    set)
        shift
        config_set_all $@
        ;;
    conn-chain)
        shift
        config_conn_chain $@
        ;;
    chain-port)
        shift
        config_chain_port $@
        ;;
    generate)
        shift
        config_generate $@
        ;;
    pull-image)
        pull_images_by_mode
        ;;
    *)
        config_help
        ;;
    esac
}
