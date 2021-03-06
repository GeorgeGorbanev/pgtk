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

require 'minitest/autorun'
require 'tmpdir'
require 'rake'
require 'yaml'
require_relative '../lib/pgtk/pgsql_task'
require_relative '../lib/pgtk/liquibase_task'
require_relative '../lib/pgtk/pool'

# Pool test.
# Author:: Yegor Bugayenko (yegor256@gmail.com)
# Copyright:: Copyright (c) 2017-2018 Yegor Bugayenko
# License:: MIT
class TestPool < Minitest::Test
  def test_basic
    Dir.mktmpdir 'test' do |dir|
      Pgtk::PgsqlTask.new(:pgsql1) do |t|
        t.dir = File.join(dir, 'pgsql')
        t.user = 'hello'
        t.password = 'A B C привет ! & | !'
        t.dbname = 'test'
        t.yaml = File.join(dir, 'cfg.yml')
        t.quiet = true
      end
      Rake::Task['pgsql1'].invoke
      Pgtk::LiquibaseTask.new(:liquibase1) do |t|
        t.master = File.join(__dir__, '../test-resources/master.xml')
        t.yaml = File.join(dir, 'cfg.yml')
        t.quiet = true
      end
      Rake::Task['liquibase1'].invoke
      yaml = YAML.load_file(File.join(dir, 'cfg.yml'))
      pool = Pgtk::Pool.new(
        port: yaml['pgsql']['port'],
        dbname: yaml['pgsql']['dbname'],
        user: yaml['pgsql']['user'],
        password: yaml['pgsql']['password']
      )
      pool.start(1)
      id = pool.exec(
        'INSERT INTO book (title) VALUES ($1) RETURNING id',
        ['Elegant Objects']
      )[0]['id'].to_i
      assert(id.positive?)
    end
  end
end
