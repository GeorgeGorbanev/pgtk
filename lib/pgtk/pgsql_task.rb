# frozen_string_literal: true

# Copyright (c) 2019 Yegor Bugayenko
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the 'Software'), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

require 'cgi'
require 'English'
require 'rake'
require 'rake/tasklib'
require 'random-port'
require 'shellwords'
require 'tempfile'
require 'yaml'
require_relative '../pgtk'

# Pgsql rake task.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2019 Yegor Bugayenko
# License:: MIT
class Pgtk::PgsqlTask < Rake::TaskLib
  attr_accessor :name
  attr_accessor :dir
  attr_accessor :fresh_start
  attr_accessor :user
  attr_accessor :password
  attr_accessor :dbname
  attr_accessor :port
  attr_accessor :yaml
  attr_accessor :quiet

  def initialize(*args, &task_block)
    @name = args.shift || :pgsql
    unless ::Rake.application.last_description
      desc 'Start a local PostgreSQL server'
    end
    task(name, *args) do |_, task_args|
      RakeFileUtils.send(:verbose, true) do
        yield(*[self, task_args].slice(0, task_block.arity)) if block_given?
        run
      end
    end
  end

  private

  def run
    home = File.expand_path(@dir)
    FileUtils.rm_rf(home) if @fresh_start
    if File.exist?(home)
      raise "Directory/file #{home} is present, use fresh_start=true"
    end
    out = "2>&1 #{@quiet ? '>/dev/null' : ''}"
    Tempfile.open do |pwfile|
      IO.write(pwfile.path, @password)
      system(
        [
          'initdb --auth=trust',
          "-D #{Shellwords.escape(home)}",
          '--username',
          Shellwords.escape(@user),
          '--pwfile',
          Shellwords.escape(pwfile.path),
          out
        ].join(' ')
      )
    end
    raise unless $CHILD_STATUS.exitstatus.zero?
    port = RandomPort::Pool.new.acquire
    pid = Process.spawn('postgres', '-k', home, '-D', home, "--port=#{port}")
    at_exit do
      `kill -TERM #{pid}`
      puts "PostgreSQL killed in PID #{pid}"
    end
    sleep 1
    attempt = 0
    begin
      system(
        [
          "createdb -h localhost -p #{port}",
          '--username',
          Shellwords.escape(@user),
          Shellwords.escape(@dbname),
          out
        ].join(' ')
      )
      raise unless $CHILD_STATUS.exitstatus.zero?
    rescue StandardError => e
      puts e.message
      sleep(5)
      attempt += 1
      raise if attempt > 10
      retry
    end
    IO.write(
      @yaml,
      {
        'pgsql' => {
          'host' => 'localhost',
          'port' => port,
          'dbname' => @dbname,
          'user' => @user,
          'password' => @password,
          'url' => [
            "jdbc:postgresql://localhost:#{port}/",
            "#{CGI.escape(@dbname)}?user=#{CGI.escape(@user)}",
            "&password=#{CGI.escape(@password)}"
          ].join
        }
      }.to_yaml
    )
    puts "PostgreSQL is running in PID #{pid}"
  end
end
