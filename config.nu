# config.nu
#
# Installed by:
# version = "0.103.0"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# This file is loaded after env.nu and before login.nu
#
# You can open this file in your default editor using:
# config nu
#
# See `help config nu` for more options
#
# You can remove these comments if you want or leave
# them for future reference.


source ~/.config/nushell/clone-user-repos.nu

# Custom lsof function to convert output to a table
def lsof [...args: string] {
    # Run lsof with optional arguments and get output as lines
    let lsof_output = (^lsof ...$args | lines)

    # Extract headers from the first line
    let headers = ($lsof_output | first | split row -r '\s+')

    # Process data rows, skipping the header
    let data = ($lsof_output | skip 1 | each { |line|
        let cols = ($line | split row -r '\s+')
        $headers | enumerate | reduce -f {} { |it, acc|
            $acc | upsert ($it.item) ($cols | get -i $it.index | default "")
        }
    })

    # Return the data as a table
    $data
}

# Initialize directory stack
$env.DIR_STACK = []

# Pushd equivalent: Add current directory to stack and change to new directory
def pushd [dir: path] {
    let current_dir = $env.PWD
    $env.DIR_STACK = ($env.DIR_STACK | prepend $current_dir)
    cd $dir
}

# Popd equivalent: Return to the last directory in the stack
def popd [] {
    if ($env.DIR_STACK | is-empty) {
        error make {msg: "Directory stack is empty"}
    }
    let target_dir = ($env.DIR_STACK | first)
    $env.DIR_STACK = ($env.DIR_STACK | skip 1)
    cd $target_dir
}

# View the stack (optional, like `dirs` in Bash)
def dirs [] {
    $env.DIR_STACK
}

# Script to find and list the 10 largest files in a directory with their sizes
# Usage: source biggest_files.nu [path]
# If no path is provided, searches from the current directory

def biggest-files [
    path: path = "."  # Directory to search (default: current directory)
] {
    # Use find to get all files, then pass to ls for size info
    let files = (
        ^find $path -type f
        | lines
        | par-each { |file|
            ls -l $file
            | get 0
            | select name size
        }
        | sort-by size --reverse
        | take 10
        | update size { |row|
            # Convert size to human-readable format
            ($row.size | into filesize)
        }
    )

    # Return the results
    $files
}
alias bgf = biggest-files

# Command to find and print files with a given extension
# Usage: find-by-ext <extension> [path]
# Example: find-by-ext txt /home/user/docs
# If no path is provided, searches from the current directory

def find-by-ext [
    extension: string,  # File extension to search for (e.g., "txt", "pdf")
    path: path = "."   # Directory to search (default: current directory)
] {
    # Use find to locate files with the given extension
    let files = (
        ^find $path -type f -name $"*.$extension"
        | lines
        | sort
    )

    # Print the results
    $files
}

# Example usage
# find-by-ext txt

alias fbx = find-by-ext
