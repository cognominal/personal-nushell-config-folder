# Path to cache file for usernames
let username_cache_file = ($env.HOME | path join ".github_username_cache")

# Function to load usernames from cache
def load-cached-usernames [] {
    if ($username_cache_file | path exists) {
        open $username_cache_file | lines | where ($it | str trim) != ""
    } else {
        []
    }
}

# Function to save username to cache
def save-username-to-cache [username: string] {
    let cached_usernames = (load-cached-usernames)
    if not ($username in $cached_usernames) {
        let new_usernames = ($cached_usernames | append $username | uniq)
        $new_usernames | str join "\n" | save -f $username_cache_file
    }
}

# Completion definition for username
def --env "nu-complete github-usernames" [] {
    load-cached-usernames
}

# Function to clone all public GitHub user repositories and create links
def clone-github-user-repos [
    username: string@"nu-complete github-usernames"    # GitHub username with completion
] {
    # Save username to cache
    save-username-to-cache $username

    # Define paths
    let home_dir = $env.HOME
    let target_dir = ($home_dir | path join $username)
    let git_dir = ($home_dir | path join "git")

    # Create target directory if it doesn't exist
    if not ($target_dir | path exists) {
        mkdir $target_dir
    }

    # Create ~/git directory if it doesn't exist
    if not ($git_dir | path exists) {
        mkdir $git_dir
    }

    # Fetch repository list using GitHub API
    let repos = (http get $"https://api.github.com/users/($username)/repos" | where private == false )

    # Check if repos is empty
    if ($repos | is-empty) {
        error make {msg: $"No public repositories found for user ($username)"}
        return
    }

    # Clone each repository and create symbolic link
    for repo in $repos {
        let repo_name = $repo.name
        let clone_path = ($target_dir | path join $repo_name)
        let link_name = $"($username)--($repo_name)"
        let link_path = ($git_dir | path join $link_name)

        # Clone if directory doesn't exist
        if not ($clone_path | path exists) {
            print $"Cloning ($repo_name)..."
            ^git clone $repo.clone_url $clone_path
        } else {
            print $"Repository ($repo_name) already exists, skipping clone"
        }

        # Create symbolic link
        if not ($link_path | path exists) {
            print $"Creating symbolic link for ($repo_name)..."
            ln -s $clone_path $link_path
        } else {
            print $"Link ($link_name) already exists, skipping"
        }
    }

    print $"Finished cloning repositories for ($username)"
}

# Example usage:
# clone-github-user-repos "usernm"
