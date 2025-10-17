#!/bin/bash

# Forum post generator for Fibaro Forum (or other forums)

# Get script directory and load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/project-config.sh"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file not found: $CONFIG_FILE"
    echo "Please create project-config.sh with your project settings."
    exit 1
fi

# Source the configuration
source "$CONFIG_FILE"

# Validate configuration
if ! validate_config; then
    echo "Error: Invalid configuration in $CONFIG_FILE"
    exit 1
fi

# Forum post generator
generate_forum_post() {
    local version=$1
    local release_notes=$2
    local github_url="https://github.com/$GITHUB_REPO"
    
    # Get artifact names for download links
    local artifact_names=($(get_artifact_names))
    
    # Build artifact download links HTML
    local artifact_links=""
    for artifact in "${artifact_names[@]}"; do
        artifact_links+="<li><a href=\"$github_url/releases/download/v$version/$artifact\">$artifact</a></li>"
    done
    
    # Convert markdown-style formatting for HTML display
    local formatted_notes=$(echo "$release_notes" | \
        sed 's/^### \(.*\)/<h4>\1<\/h4>\n/g' | \
        sed 's/^## \(.*\)/<h3>\1<\/h3>\n/g' | \
        sed 's/^- \(.*\)/<li>\1<\/li>/g' | \
        sed 's/^\* \(.*\)/<li>\1<\/li>/g' | \
        sed 's/^\*\(.*\)\*$/<p><em>\1<\/em><\/p>/g' | \
        awk 'BEGIN{in_list=0} 
             /^<li>/ {
                 if(!in_list){print "<ul>"; in_list=1} 
                 print; next
             } 
             {
                 if(in_list){print "</ul>"; in_list=0} 
                 if($0 != "") print
             } 
             END{if(in_list)print "</ul>"}' | \
        sed 's/\*\*\([^*]*\)\*\*/\<strong\>\1\<\/strong\>/g')
    
    # Create HTML forum post in configured notes directory
    mkdir -p "$NOTES_DIR"
    local temp_file=$(mktemp)
    cat > "$temp_file" << EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>$PROJECT_NAME v$version - Forum Post</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: white;
            color: #333;
            max-width: 800px;
            margin: 20px auto;
            padding: 20px;
            line-height: 1.6;
        }
        .post-content {
            background: #fafafa;
            border: 1px solid #e1e1e1;
            border-radius: 8px;
            padding: 20px;
            margin: 20px 0;
        }
        .copy-button {
            background: #0366d6;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 4px;
            cursor: pointer;
            font-size: 14px;
            margin-bottom: 10px;
        }
        .copy-button:hover {
            background: #0256cc;
        }
        .forum-link {
            background: #28a745;
            color: white;
            text-decoration: none;
            padding: 10px 20px;
            border-radius: 4px;
            display: inline-block;
            margin-left: 10px;
        }
        .forum-link:hover {
            background: #218838;
        }
        h2 { color: #0366d6; }
        h3 { color: #586069; }
        code { background: #f6f8fa; padding: 2px 4px; border-radius: 3px; }
        .emoji { font-size: 1.2em; }
    </style>
</head>
<body>
    <h1>$PROJECT_NAME v$version - Forum Post Helper</h1>
    
    <div>
        <button class="copy-button" onclick="copyToClipboard()">📋 Copy Forum Post</button>
EOF

    # Add forum link if configured
    if [ -n "$FORUM_URL" ]; then
        cat >> "$temp_file" << EOF
        <a href="$FORUM_URL" class="forum-link" target="_blank">🌐 Open Forum Thread</a>
EOF
    fi

    cat >> "$temp_file" << EOF
    </div>
    
    <div class="post-content" id="forumPost">
<h2>🚀 $PROJECT_NAME - Release v$version</h2>

$formatted_notes

<h3>📥 <strong>Download</strong></h3>
<ul>
<li><strong>GitHub Releases</strong>: <a href="$github_url/releases/tag/v$version">$github_url/releases/tag/v$version</a></li>
<li><strong>Direct Downloads</strong>:
<ul>
$artifact_links
</ul>
</li>
</ul>

<h3>📚 <strong>Documentation</strong></h3>
<ul>
<li><strong>Full Documentation</strong>: <a href="$DOCUMENTATION_URL">$DOCUMENTATION_URL</a></li>
</ul>

<hr>
<p><em>This release was automatically generated from commit $(git rev-parse --short HEAD)</em></p>
    </div>

    <script>
        function copyToClipboard() {
            const postContent = document.getElementById('forumPost');
            const range = document.createRange();
            range.selectNode(postContent);
            window.getSelection().removeAllRanges();
            window.getSelection().addRange(range);
            
            try {
                document.execCommand('copy');
                const button = document.querySelector('.copy-button');
                const originalText = button.textContent;
                button.textContent = '✅ Copied!';
                button.style.background = '#28a745';
                setTimeout(() => {
                    button.textContent = originalText;
                    button.style.background = '#0366d6';
                }, 2000);
            } catch (err) {
                alert('Please manually select and copy the content below');
            }
            
            window.getSelection().removeAllRanges();
        }
    </script>
</body>
</html>
EOF

    # Move temp file to final location atomically
    mv "$temp_file" "$NOTES_DIR/release-v$version.html"
    
    # Wait for file to be fully available and verify it has content
    local retries=0
    while [ $retries -lt 10 ]; do
        if [ -s "$NOTES_DIR/release-v$version.html" ]; then
            break
        fi
        sleep 0.1
        retries=$((retries + 1))
    done
    
    echo "✅ Forum post created: $NOTES_DIR/release-v$version.html"
    if [ -n "$FORUM_URL" ]; then
        echo "📋 Copy and paste this content to: $FORUM_URL"
    fi
}

# Export function for use in release script
export -f generate_forum_post

# If script is run directly (not sourced), call the function
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ $# -ne 2 ]; then
        echo "Usage: $0 <version> <release_notes>"
        echo "Example: $0 1.0.0 'Bug fixes and improvements'"
        exit 1
    fi
    
    generate_forum_post "$1" "$2"
fi
