#!/usr/bin/env ruby
# frozen_string_literal: true

# see:
# https://github.com/evernote/evernote-oauth-ruby?ref=https://githubhelp.com
# https://dev.evernote.com/doc/articles/search.php
# https://www.rubydoc.info/gems/evernote-thrift/1.24.0/Evernote/EDAM/NoteStore/NoteFilter
require 'bundler/setup'
Bundler.require(:default)

LOGFILE = File.join(Dir.home, '.log', 'rubynote.log')
CREDENTIALS_PATH = File.join(Dir.home, '.credentials', 'rubynote.yaml')

SERVICE_HOST = 'www.evernote.com'
# Url to view the note via the web client
# e.g. https://www.evernote.com/client/web#/note/cd43781e-5bc1-4c3d-8f11-48a5f2fdb60d
NOTE_WEBCLIENT_URL = "https://#{SERVICE_HOST}/client/web#/note/%<note_guid>s".freeze
# Direct note link (see https://dev.evernote.com/doc/articles/note_links.php)
# e.g. https://www.evernote.com/shard/s1/nl/2079/cd43781e-5bc1-4c3d-8f11-48a5f2fdb60d
NOTE_LINK = "https://#{SERVICE_HOST}/shard/%<shard_id>s/nl/%<user_id>s/%<note_guid>s".freeze

class Rubynote
  extend Memoist

  attr_reader :auth_token

  def client
    credentials = YAML.load_file CREDENTIALS_PATH
    @auth_token = credentials[:auth_token]
    @client = EvernoteOAuth::Client.new(
      token: credentials[:auth_token],
      consumer_key: credentials[:oauth_consumer_key],
      consumer_secret: credentials[:oauth_consumer_secret],
      sandbox: credentials[:sandbox]
    )
    @client
  end
  memoize :client

  def user_store
    client.user_store
  end
  memoize :user_store

  def en_user
    user_store.getUser(auth_token)
  end
  memoize :en_user

  def note_store
    client.note_store
  end
  memoize :note_store

  def notebooks
    note_store.listNotebooks(auth_token)
  end
  memoize :notebooks

  def tags
    note_store.listTags
  end
  memoize :tags

  def tag_counts
    collection_counts = note_store.findNoteCounts(auth_token, Evernote::EDAM::NoteStore::NoteFilter.new, false)
    Hash[collection_counts.tagCounts.map { |k, v| [k, v] }]
  end
end

class Rubynote_CLI < Thor
  class_option :verbose, type: :boolean

  no_commands do
    def search_note(rubynote, count)
      filter = Evernote::EDAM::NoteStore::NoteFilter.new
      filter.words = options[:query]
      filter.order = Evernote::EDAM::Type::NoteSortOrder::RELEVANCE

      spec = Evernote::EDAM::NoteStore::NotesMetadataResultSpec.new
      spec.includeTitle               = true
      spec.includeContentLength       = true
      spec.includeCreated             = true
      spec.includeUpdated             = true
      spec.includeNotebookGuid        = true
      spec.includeAttributes          = true
      spec.includeTagGuids            = true
      spec.includeLargestResourceMime = true
      spec.includeLargestResourceSize = true

      offset = 0
      #
      # note that returned results will be limited to 128 notes
      # due to issue documented here: https://discussion.evernote.com/forums/topic/139586-app-limited-to-no-more-than-128-note-metadata-using-evernote-api-with-developer-token/
      #
      result = rubynote.note_store.findNotesMetadata(rubynote.auth_token, filter, offset, count, spec)
      puts "notes returned = #{result.notes.length}" if options[:verbose]
      puts "total notes = #{result.totalNotes}" if options[:verbose]

      # Reduces the count by the amount of notes already retrieved
      # In none are initially retrieved, presume no more exist to retrieve
      count = result.notes.empty? ? 0 : [count - result.notes.length, 0].max
      # Evernote api will only return so many notes in one go. Checks for more
      # notes to come whilst obeying count rules
      while (result.totalNotes > result.notes.length) && count.positive?
        puts 'getting more notes' if options[:verbose]
        offset = result.notes.length
        add_result = rubynote.note_store.findNotesMetadata(rubynote.auth_token, filter, offset, count, spec)
        puts "additional result = #{add_result.notes.length}" if options[:verbose]

        if add_result.notes.empty?
          count = 0
        else
          result.notes.append add_result.notes
          count = [count - add_result.notes.length, 0].max
        end
        puts "targeting #{result.totalNotes}" if options[:verbose]
        puts "to go = #{count}" if options[:verbose]
      end

      result
    end

    def format_date(date)
      date && Time.at(date / 1000).strftime('%Y-%m-%d %H:%M:%S')
    end
  end

  desc 'create', ''
  method_option :content,          type: :string, default: ''
  method_option :dry_run,          type: :boolean
  method_option :notebook_guid,    type: :string
  method_option :resource,         type: :string, repeatable: true
  method_option :source_url,       type: :string
  method_option :tag,              type: :string, repeatable: true
  method_option :title,            type: :string, default: 'Untitled Note'
  def create
    note = Evernote::EDAM::Type::Note.new(
      title: options[:title],
      tagNames: options[:tag]
    )
    note.notebookGuid = options[:notebook_guid] if options[:notebook_guid]

    if options[:source_url]
      note.attributes = Evernote::EDAM::Type::NoteAttributes.new if note.attributes.nil?
      note.attributes.sourceURL = options[:source_url]
    end

    resource_refs = []
    options[:resource]&.each do |filename|
      data = File.open(filename, 'rb', &:read)
      mimetype = Marcel::MimeType.for Pathname.new(filename)
      body_hash = note.add_resource(File.basename(filename), data, mimetype)
      resource_refs.append "<en-media type=\"#{mimetype}\" hash=\"#{body_hash}\"/>"
    end

    note.content = <<~END_CONTENT
      <?xml version="1.0" encoding="UTF-8"?>
      <!DOCTYPE en-note SYSTEM "http://xml.evernote.com/pub/enml2.dtd">
      <en-note>
        #{resource_refs.join("\n  ")}
      </en-note>
    END_CONTENT

    if options[:dry_run]
      pp note
    else
      rubynote = Rubynote.new
      created_note = rubynote.note_store.createNote(rubynote.auth_token, note)
      pp created_note if options[:verbose]
      # puts "NoteLink: #{format NOTE_LINK, { shard_id: rubynote.en_user.shardId, user_id: rubynote.en_user.id, note_guid: created_note.guid }}"
      puts "created: #{format NOTE_WEBCLIENT_URL, { note_guid: created_note.guid }}"
    end
  end

  desc 'find', ''
  method_option :count,            type: :numeric, desc: 'number of notes to retrieve', default: 20
  method_option :query,            type: :string,  desc: 'search terms, fully described at https://dev.evernote.com/doc/articles/search_grammar.php'
  method_option :show_ctime,       type: :boolean, desc: 'show creation time'
  method_option :show_guid,        type: :boolean, desc: 'show note guid'
  method_option :show_mtime,       type: :boolean, desc: 'show modification (update) time'
  method_option :show_notebook,    type: :boolean, desc: 'show notebook name'
  method_option :show_tag_guids,   type: :boolean, desc: 'show tag guids'
  method_option :show_tags,        type: :boolean, desc: 'show tag names'
  def find
    rubynote = Rubynote.new
    result = search_note(rubynote, options[:count])
    result.notes.each do |note|
      pp note if options[:verbose]
      puts [
        (format('%16s',   note.guid) if options[:show_guid]),
        (format('[%19s]', format_date(note.created)) if options[:show_ctime]),
        (format('[%19s]', format_date(note.updated)) if options[:show_mtime]),
        format('%-64s',   note.title),
        (format('%-16s',  rubynote.notebooks.find { |notebook| notebook.guid == note.notebookGuid }&.name) if options[:show_notebook]),
        (format('%16s',   note.tagGuids) if options[:show_tag_guids]),
        (format('%16s',   rubynote.tags.select { |tag| note.tagGuids.include? tag.guid }&.map(&:name)&.sort) if options[:show_tags])
      ].reject(&:nil?).join(' ')
    end
  end

  desc 'notebook-list', ''
  method_option :show_ctime,       type: :boolean, desc: 'show creation time'
  method_option :show_guid,        type: :boolean, desc: 'show notebook guid'
  method_option :show_mtime,       type: :boolean, desc: 'show modification (update) time'
  def notebook_list
    rubynote = Rubynote.new
    rubynote.notebooks.each do |notebook|
      puts [
        (format('%16s',   notebook.guid) if options[:show_guid]),
        (format('[%19s]', format_date(notebook.serviceCreated)) if options[:show_ctime]),
        (format('[%19s]', format_date(notebook.serviceUpdated)) if options[:show_mtime]),
        format('%-64s',   notebook.name)
      ].reject(&:nil?).join(' ')
    end
  end

  desc 'show', ''
  method_option :raw,              type: :boolean, desc: 'show the raw note body'
  method_option :query,            type: :string,  desc: 'search terms, fully described at https://dev.evernote.com/doc/articles/search_grammar.php'
  def show
    rubynote = Rubynote.new
    note = search_note(rubynote, 1).notes.first
    return if note.nil?

    content = rubynote.note_store.getNoteContent(rubynote.auth_token, note.guid)
    if options[:raw]
      puts content
    else
      puts "Title: #{note.title}"
      puts "Notebook: #{note.notebookGuid} \"#{rubynote.notebooks.find { |notebook| notebook.guid == note.notebookGuid }&.name}\""
      puts "Created: #{format_date(note.created)}"
      puts "Updated: #{format_date(note.updated)}"
      puts "NoteLink: #{format NOTE_LINK, { shard_id: rubynote.en_user.shardId, user_id: rubynote.en_user.id, note_guid: note.guid }}"
      puts "WebClientURL: #{format NOTE_WEBCLIENT_URL, { note_guid: note.guid }}"

      fields = %w[subjectDate latitude longitude altitude author source
                  sourceURL sourceApplication shareDate placeName contentClass
                  applicationData lastEditedBy classifications creatorId
                  lastEditorId sharedWithBusiness conflictSourceNoteGuid
                  noteTitleQuality reminderOrder reminderTime reminderDoneTime]
      fields.each do |field|
        value = note.attributes.send field
        puts "attribute.#{field}: #{value.inspect}" if value
      end

      puts "Tags: #{rubynote.tags.select { |tag| note.tagGuids.include? tag.guid }&.map(&:name)}"
      puts 'Content:'
      # TODO: handle <en-media> tags in content
      puts Loofah.document(content).to_text.chomp
    end
  end

  desc 'tag-list', ''
  method_option :depth,            type: :numeric, desc: 'depth of hierarchy, implies --tree'
  method_option :show_guid,        type: :boolean, desc: 'show tag guid'
  method_option :show_parent,      type: :boolean, desc: 'show tag parent'
  method_option :show_parent_guid, type: :boolean, desc: 'show tag parent guid'
  method_option :show_note_count,  type: :boolean, desc: 'show count of notes with tag'
  method_option :tree,             type: :boolean, desc: 'display tag hierarchy as tree'
  def tag_list
    as_tree = options[:tree] || options[:depth]&.positive?

    rubynote = Rubynote.new
    tag_counts = rubynote.tag_counts if options[:show_note_count]
    nodes = [] # for as_tree
    rubynote.tags&.collect { |t| [t.name.downcase, t] }&.sort&.collect { |s| s[1] }&.each do |tag|
      nodes.push({ id: tag.guid, name: tag.name, parent_id: tag.parentGuid })

      next if as_tree

      puts tag.parentGuid if options[:show_parent_guid]
      puts tag.guid if options[:show_guid]
      puts rubynote.tags.find { |parent| parent.guid == tag.parentGuid }&.name if options[:show_parent]
      count = options[:show_note_count] ? " (#{tag_counts[tag.guid]})" : ''
      puts "#{tag.name}#{count}"
    end

    return unless as_tree

    # Initialize tree with a default nil root
    tree = { nil => { children: [] } }

    nodes&.each do |node|
      current_default = { parent_id: node[:parent_id], name: node[:name] }
      tree[node[:id]] ||= current_default
      tree[node[:id]] = tree[node[:id]].merge(current_default)

      parent_default = { children: [] }
      tree[node[:parent_id]] ||= parent_default
      tree[node[:parent_id]] = parent_default.merge(tree[node[:parent_id]])
      tree[node[:parent_id]][:children].push(node[:id])
    end

    # https://github.com/kddnewton/tree/blob/main/tree.rb
    visit_children = lambda do |node, branch, prefix = '', depth|
      return if options[:depth] && depth > options[:depth]

      children = branch[node][:children]
      last_idx = children.nil? ? 0 : children.length - 1

      children&.each_with_index do |child, idx|
        subtags = branch[child][:children] ? '┬' : '─'
        pointer, preadd = idx == last_idx ? ["└───#{subtags} ", '    '] : ["├───#{subtags} ", '│   ']
        count = options[:show_note_count] ? " (#{tag_counts[child]})" : ''
        puts "#{prefix}#{pointer}#{branch[child][:name]}#{count}"
        visit_children.call(child, branch, "#{prefix}#{preadd}", depth + 1)
      end
    end

    tree[nil][:children]&.each do |root|
      count = options[:show_note_count] ? " (#{tag_counts[root]})" : ''
      puts "#{tree[root][:name]}#{count}"
      visit_children.call(root, tree, '', 1)
    end
  end
end

Rubynote_CLI.start
