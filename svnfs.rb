#!/usr/bin/ruby
# 
# Copyright (C) 2009, Osamu Matsumoto < osamu.matsumoto@gmail.com >
# You can redistribute it and/or modify it under GPL2.

# = References = 
# - http://rubyforge.org/projects/fusefs/

require 'fusefs'

$debug = true
module SvnWrap

  def svn_config(repository)
    @repository = repository
  end

  def svn_log(path)
    puts "svn_log : #{path}" if $debug
    cmd = "svn log #{File.join(@repository,path)}"
    io = IO.popen(cmd)
    buffer = io.readlines.join
    io.close
    buffer
  end

  def svn_revisions(path)
    puts "svn_revision: #{path}" if $debug
    log = svn_log(path.gsub(/svn-revision/,''))
    log.scan(/(^r\d+)\s+\|/).flatten
  end

  def svn_info(path, rev='HEAD')
    puts "svn_info :#{path}@#{rev}" if $debug
    items = {}
    cmd = "svn -r #{rev} info #{File.join(@repository,path)}"
    io = IO.popen(cmd)
    io.each { |line|
      key,value = line.chomp.split(/\s*:\s*/)
      items[key] = value
    }
    io.close
    items
  end

  def svn_cat(path, rev='HEAD')
    cmd = "svn -r #{rev} cat #{File.join(@repository,path)}"
    io = IO.popen(cmd)
    buffer =  io.readlines.join
    io.close
    buffer
  end

  def svn_file?(path,rev='HEAD')
    puts "svn_file?; #{path}" if $debug
    svn_info(path, rev)['Node Kind'] == 'file'
  end
  
  def svn_directory?(path, rev='HEAD')
    svn_info(path, rev)['Node Kind'] == 'directory'
  end
  
  def svn_ls(path,rev='HEAD')
    puts "svn_ls: #{path}@#{rev}" if $debug
    items = []
    cmd= "svn -r #{rev} ls #{File.join(@repository,path)}"
    io = IO.popen(cmd)
    io.each {|el|
      items.push(el.chomp.gsub(/\/$/,''))
    }
    io.close
    p items
    items
  end

  module_function :svn_config, :svn_ls,:svn_info
end


class SvnDir < FuseFS::MetaDir
  include FuseFS
  include SvnWrap

  def initialize(dir, repositorydir)
    @basedir = dir
    @repository = repositorydir
  end

  def contents(path)
    puts "contents; #{path}" if $debug
    case path
    when /svn-revision\/*$/
      puts "revisions dir mode" if $debug
      nodes = svn_revisions(path)
    when /svn-revision\/r\d+/
      puts "revision view mode" if $debug
      path, rev = analyze_svnfs_path(path)
      nodes = svn_ls(path,rev)
    else
      puts "normal mode" if $debug
      nodes = svn_ls(path,'HEAD')
      nodes.push("svn-revision")
      nodes.push("svn-log")
      nodes.push("svn-info")
    end
    nodes
  end
  
  def file?(path)
    puts "file?" if $debug
    path,rev = analyze_svnfs_path(path)
    virtual_file?(path) or svn_file?(path,rev)
  end
  
  def directory?(path)
    puts "directory?" if $debug
    path,rev = analyze_svnfs_path(path)
    if virtual_directory?(path) 
      puts "is virtual directory"  if $debug
      true
    elsif virtual_file?(path)
      puts "is virtual file."    if $debug
      false
    else  
      svn_directory?(path)
    end
  end

  def read_file(path)
    puts "read_file?" if $debug
    realpath, rev = analyze_svnfs_path(path)
    case File.basename(realpath)
    when /svn-log/
      return svn_log(Regexp.last_match.pre_match)
    when /svn-info/
      buffer = ""
      items = svn_info(Regexp.last_match.pre_match, rev)
      items.each { |key,value|
        buffer+= "#{key} : #{value}\n" if key
      }
      buffer
    else
      return svn_cat(realpath,rev)
    end
  end

  def can_delete?(path)
    false
  end

  def can_write?(path)
    false
  end

  private
  def virtual_directory?(path)
    path =~ /svn-revision/
  end
  
  def virtual_file?(path)
    path =~ /svn-log|svn-info/
  end

  def analyze_svnfs_path(path)
    case path
    when /svn-revision\/r(\d+)\/*/
      puts "analyze: #{path} #{$`} #{$'}" if $debug
      [Regexp.last_match.pre_match + Regexp.last_match.post_match, "#{$1}"]
    when /svn-revision\/*$/
      puts "analyze: #{path} #{$`} #{$'}" if $debug
      [Regexp.last_match.pre_match + Regexp.last_match.post_match, "HEAD"]
    else
      [path,'HEAD']
    end
  end

end


if ARGV.length != 2 
  puts "Usage: svnfs <repository> <directory>"
  exit
end

ENV['LANG']="C"
repository = ARGV[0]
dstdir = File.expand_path(ARGV[1])
SvnWrap.svn_config(repository)

if  SvnWrap.svn_info("/").empty?
  puts "#{repository} is not valid svn repository."
  exit
end


begin 
  svndir = SvnDir.new(dstdir, repository)
  puts "mount dir : #{dstdir}"
  puts "repository: #{repository}"


  FuseFS.set_root(svndir)
  FuseFS.mount_under dstdir
  FuseFS.run

ensure
  puts "unmount : #{dstdir}"
  FuseFS.unmount
end

