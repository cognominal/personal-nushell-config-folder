# Path to cache file for usernames
let username_cache_file = ($env.HOME | path join ".github_username_cache")

# Path to stars output file
let stars_file = ($env.HOME | path join "git" "github-stars")

# Load GitHub token from .env file
let env_file = ($env.HOME | path join ".env")
let github_token = if ($env_file | path exists) {
    open $env_file
    | lines
    | parse "{key}={value}"
    | where key == "GITHUB_TOKEN"
    | get value
    | first
    | default ""
} else {
    ""
}

# Function to parse and validate GitHub URLs
def parse-github-url [url: string] {
    try {
        # List of supported patterns: tuple of (prefix, parse_pattern_with_git, parse_pattern_without_git)
        let patterns = [
            {prefix: "https://github.com/", with_git: "https://github.com/{username}/{reponame}.git", without_git: "https://github.com/{username}/{reponame}"},
            {prefix: "git@github.com:", with_git: "git@github.com:{username}/{reponame}.git", without_git: "git@github.com:{username}/{reponame}"},
            {prefix: "https://gitlab.com/", with_git: "https://gitlab.com/{username}/{reponame}.git", without_git: "https://gitlab.com/{username}/{reponame}"},
            {prefix: "git@bitbucket.org:", with_git: "git@bitbucket.org:{username}/{reponame}.git", without_git: "git@bitbucket.org:{username}/{reponame}"}
        ]
        for pattern in $patterns {
            if ($url | str starts-with $pattern.prefix) {
                let parsed = ($url | parse $pattern.with_git)
                if ($parsed | is-empty) {
                    let parsed = ($url | parse $pattern.without_git)
                    if ($parsed | is-empty) {
                        return null
                    }
                    let username = ($parsed | get username | first | default "")
                    let reponame = ($parsed | get reponame | first | default "")
                    if ($username == "" or $reponame == "" or ($reponame | str contains "/")) {
                        return null
                    }
                    return { username: $username, reponame: $reponame }
                } else {
                    let username = ($parsed | get username | first | default "")
                    let reponame = ($parsed | get reponame | first | default "")
                    if ($username == "" or $reponame == "" or ($reponame | str contains "/")) {
                        return null
                    }
                    return { username: $username, reponame: $reponame }
                }
            }
        }
        return null
    } catch {
        return null
    }
}

# Function to test supported GitHub URL formats
def test-github-urls [] {
    let test_cases = [
        # Valid GitHub URLs
        {url: "https://github.com/bmdavis419/Svelte-Stores-Streams-Effect", expected: {username: "bmdavis419", reponame: "Svelte-Stores-Streams-Effect"}},
        {url: "https://github.com/usernm/repo1.git", expected: {username: "usernm", reponame: "repo1"}},
        {url: "git@github.com:usernm/repo2.git", expected: {username: "usernm", reponame: "repo2"}},
        {url: "git@github.com:bmdavis419/project", expected: {username: "bmdavis419", reponame: "project"}},
        # Invalid or non-GitHub URLs
        {url: "https://gitlab.com/usernm/repo3", expected: null},
        {url: "https://github.com/invalid", expected: null},
        {url: "git@bitbucket.org:usernm/repo4", expected: null},
        {url: "invalid_url", expected: null},
        {url: "https://github.com", expected: null}
    ]
    
    let results = ($test_cases | each { |case|
        let result = (parse-github-url $case.url)
        {
            url: $case.url,
            valid: (not ($result | is-empty)),
            username: ($result.username? | default ""),
            reponame: ($result.reponame? | default ""),
            expected: ($case.expected | to json)
        }
    })
    
    $results | table
}

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

# Function to get star counts for .git repos in the current directory
def collect-github-stars [] {
    # Load existing github-stars data if it exists
    let existing_stars = (try {
        if ($stars_file | path exists) {
            let data = (open $stars_file)
            if ($data | describe | str contains "list<record") {
                $data
            } else {
                print $"Warning: ($stars_file) is not a valid table, ignoring existing data"
                print $"File contents: ($data | to json)"
                []
            }
        } else {
            []
        }
    } catch {
        print $"Warning: Failed to load ($stars_file), starting with empty data"
        []
    })
    
    # Find directories in current folder containing .git
    let repos = (ls | where type == dir | where ($it.name | path join ".git" | path exists))
    
    # Initialize table for new results
    let new_results = []
    
    # Process each repo
    for repo in $repos {
        let repo_path = $repo.name
        
        # Change to repo directory to get git config
        cd $repo_path
        
        # Get remote URL for origin
        let remote_url = (try {
            ^git config --get remote.origin.url
        } catch {
            print $"Skipping ($repo_path): No valid git remote found"
            cd -
            continue
        })
        
        # Parse and validate URL
        let repo_info = (parse-github-url $remote_url)
        if ($repo_info | is-empty) {
            print $"Skipping ($repo_path): Invalid or non-GitHub remote URL: ($remote_url)"
            cd -
            continue
        }
        
        let username = $repo_info.username
        let repo_name = $repo_info.reponame
        let repo_display = $"($username)--($repo_name)"
        
        # Get star count from GitHub API with authentication
        let api_url = $"https://api.github.com/repos/($username)/($repo_name)"
        let star_count = (try {
            if ($github_token | is-empty) {
                (http get $api_url).stargazers_count
            } else {
                (http get --headers { Authorization: $"Bearer ($github_token)" } $api_url).stargazers_count
            }
        } catch {
            0  # In case of API error or rate limit
        })
        
        # Append to new results
        let new_results = ($new_results | append {repo: $repo_display, stars: $star_count})
        
        # Return to original directory
        cd -
    }
    
    # Merge existing and new results, updating stars for matching repos
    let merged_results = ($existing_stars
        | where not (repo in ($new_results.repo))  # Keep existing entries not in new results
        | append $new_results                     # Add new/updated entries
        | uniq-by repo                            # Ensure no duplicates
        | sort-by repo)                           # Sort alphabetically by repo
    
    # Save merged results to file
    $merged_results | save -f $stars_file
    
    if ($repos | is-empty) and ($existing_stars | is-empty) {
        print "No Git repositories found in current directory and no existing star data"
    } else {
        print $"Updated star counts in ($stars_file)"
    }
}

# Function to link existing repos in the current directory and update stars
def link-existing-repos [] {
    let git_dir = ($env.HOME | path join "git")
    
    # Ensure ~/git exists
    if not ($git_dir | path exists) {
        mkdir $git_dir
    }
    
    # Find directories in current folder containing .git
    let repos = (ls | where type == dir | where ($it.name | path join ".git" | path exists))
    
    # Process each repo
    for repo in $repos {
        let repo_path = $repo.name
        
        # Change to repo directory to get git config
        cd $repo_path
        
        # Get remote URL for origin
        let remote_url = (try {
            ^git config --get remote.origin.url
        } catch {
            print $"Skipping ($repo_path): No valid git remote found"
            cd -
            continue
        })
        
        # Parse and validate URL
        let repo_info = (parse-github-url $remote_url)
        if ($repo_info | is-empty) {
            print $"Skipping ($repo_path): Invalid or non-GitHub remote URL: ($remote_url)"
            cd -
            continue
        }
        
        let username = $repo_info.username
        let repo_name = $repo_info.reponame
        let link_name = $"($username)--($repo_name)"
        let link_path = ($git_dir | path join $link_name)
        
        # Create symbolic link if it doesn't exist
        if not ($link_path | path exists) {
            print $"Creating symbolic link for ($repo_name)..."
            ln -s ($repo_path | path expand) $link_path
        } else {
            print $"Link ($link_name) already exists, skipping"
        }
        
        # Save username to cache
        save-username-to-cache $username
        
        # Return to original directory
        cd -
    }
    
    # Update star counts
    collect-github-stars
    
    if ($repos | is-empty) {
        print "No Git repositories found in current directory"
    } else {
        print "Finished linking existing repositories and updating stars"
    }
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

    # Fetch repository list using GitHub API with authentication
    let repos = (try {
        if ($github_token | is-empty) {
            http get $"https://api.github.com/users/($username)/repos" | where type == "public"
        } else {
            http get --headers { Authorization: $"Bearer ($github_token)" } $"https://api.github.com/users/($username)/repos" | where type == "public"
        }
    } catch {
        error make {msg: $"Failed to fetch repositories for user ($username). Check username or GitHub token."}
        return
    })

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

    # Update star counts
    collect-github-stars

    print $"Finished cloning repositories for ($username)"
}

# Example usage:
# test-github-urls
# clone-github-user-repos "usernm"
# link-existing-repos
# collect-github-stars
# To view stars:
# open ~/git/github-stars | table
