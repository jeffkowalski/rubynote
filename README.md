# rubynote

A command-line client for Evernote.

rubynote lets you create, find, and inspect Evernote notes, notebooks, and
tags from the terminal, making it easy to script Evernote workflows — bulk
uploads, searches, and tag reports — without touching the web or desktop
clients.

## Requirements

- Ruby (with [bundler](https://bundler.io/))
- An Evernote account and a developer auth token
  (see [Evernote's Ruby quick-start](https://dev.evernote.com/doc/start/ruby.php))

## Installation

Clone this repository and install the dependencies:

```sh
git clone <this-repo> rubynote
cd rubynote
bundle install
```

To make `rubynote` available on your `PATH`, create a small wrapper script
(e.g. `~/bin/rubynote`) that points at this checkout:

```sh
#!/usr/bin/env sh
env -i HOME=$HOME PATH=$PATH \
    BUNDLE_GEMFILE=/path/to/rubynote/Gemfile \
    bundle exec /path/to/rubynote/rubynote.rb "$@"
```

## Testing

```sh
bundle exec ruby test/notebook_guid_test.rb
```

## Configuration

rubynote reads its credentials from `~/.credentials/rubynote.yaml`:

```yaml
:auth_token: "S=s1:U=xxxx:E=..."
:oauth_consumer_key: "your-consumer-key"
:oauth_consumer_secret: "your-consumer-secret"
:sandbox: false
```

- `auth_token` — your Evernote developer token
- `oauth_consumer_key` / `oauth_consumer_secret` — your API consumer credentials
- `sandbox` — set `true` to run against Evernote's sandbox service instead of
  production

## Usage

```
rubynote COMMAND [OPTIONS]
```

Every command accepts `--verbose` for additional diagnostic output.

### create

Create a new note, optionally attaching files as resources.

```sh
rubynote create --title "Receipt" --resource scan.pdf --tag receipts --tag 2026
```

| Option | Description |
|---|---|
| `--title TITLE` | Note title (default: `Untitled Note`) |
| `--content CONTENT` | Note body as plain text; each line becomes a paragraph (default: empty) |
| `--resource FILE` | Attach a file; repeatable. MIME type is detected automatically |
| `--tag TAG` | Apply a tag; repeatable |
| `--notebook NAME` | Place the note in the notebook with this exact name; fails if no such notebook exists |
| `--notebook-guid GUID` | Place the note in a specific notebook by GUID (takes precedence over `--notebook`) |
| `--source-url URL` | Set the note's source URL attribute |
| `--dry-run` | Print the note that would be created without sending it |

On success, prints a link to the created note in the Evernote web client.

### find

Search for notes and list them, one per line.

```sh
rubynote find --query 'tag:receipts created:20260101' --show-ctime --show-tags
```

| Option | Description |
|---|---|
| `--query QUERY` | Search terms, using [Evernote's search grammar](https://dev.evernote.com/doc/articles/search_grammar.php) |
| `--count N` | Number of notes to retrieve (default: 20) |
| `--show-guid` | Show each note's GUID |
| `--show-ctime` | Show creation time |
| `--show-mtime` | Show modification time |
| `--show-notebook` | Show notebook name |
| `--show-tags` | Show tag names |
| `--show-tag-guids` | Show tag GUIDs |

Results are ordered by relevance. Large result sets are fetched in batches
automatically.

### show

Display the single most relevant note matching a query, including its
metadata, attributes, tags, and content rendered as plain text.

```sh
rubynote show --query 'intitle:"Receipt"'
```

| Option | Description |
|---|---|
| `--query QUERY` | Search terms, using [Evernote's search grammar](https://dev.evernote.com/doc/articles/search_grammar.php) |
| `--raw` | Print the raw ENML note body instead of formatted output |

### notebook-list

List all notebooks.

```sh
rubynote notebook-list --show-guid
```

| Option | Description |
|---|---|
| `--show-guid` | Show each notebook's GUID |
| `--show-ctime` | Show creation time |
| `--show-mtime` | Show modification time |

### tag-list

List all tags, flat (sorted alphabetically) or as a hierarchy.

```sh
rubynote tag-list --tree --show-note-count
```

| Option | Description |
|---|---|
| `--tree` | Display the tag hierarchy as a tree |
| `--depth N` | Limit tree depth to N levels (implies `--tree`) |
| `--show-note-count` | Show the number of notes carrying each tag |
| `--show-guid` | Show each tag's GUID |
| `--show-parent` | Show each tag's parent name |
| `--show-parent-guid` | Show each tag's parent GUID |

## Examples

Upload a scanned document with tags:

```sh
rubynote create --title "insurance-policy.pdf" \
                --resource "insurance-policy.pdf" \
                --tag "2026" --tag "insurance"
```

Review the most recent notes with timestamps and notebooks:

```sh
rubynote find --query 'created:day-7' --show-ctime --show-notebook
```

Audit tag usage across the account:

```sh
rubynote tag-list --tree --show-note-count
```

## References

- [Evernote Ruby quick-start](https://dev.evernote.com/doc/start/ruby.php)
- [Evernote search grammar](https://dev.evernote.com/doc/articles/search_grammar.php)
- [evernote-oauth-ruby](https://github.com/evernote/evernote-oauth-ruby)
