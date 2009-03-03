#!/usr/bin/ruby

require 'svn/ra'
require 'svn/client'

path = "file:///home/osamu/project/svnfs/test/test-repo"

repo = Svn::Repos.open( path )
history = repo.fs.history("/", 0 , repo.fs.youngest_rev)
revision = (history.size.zero?) ? 0 : history.first[1]
puts revision

