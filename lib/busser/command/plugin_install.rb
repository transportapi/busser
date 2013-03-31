# -*- encoding: utf-8 -*-
#
# Author:: Fletcher Nichol (<fnichol@nichol.ca>)
#
# Copyright (C) 2013, Fletcher Nichol
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'rubygems/dependency_installer'
require 'busser/thor'

module Busser

  module Command

    # Plugin install command.
    #
    # @author Fletcher Nichol <fnichol@nichol.ca>
    #
    class PluginInstall < Busser::Thor::BaseGroup

      argument :plugins, :type => :array

      class_option :force_postinstall, :type => :boolean, :default => false,
        :desc => "Run the plugin's postinstall if it is already installed"

      def install_all
        silence_gem_ui!
        plugins.each { |plugin| install(plugin) }
      end

      private

      def install(plugin)
        gem_name, version = plugin.split("@")
        name = gem_name.sub(/^busser-/, '')

        if options[:force_postinstall] || install_gem(gem_name, version, name)
          load_plugin(name)
          run_postinstall(name)
        end
      end

      def install_gem(gem, version, name)
        install_arg = gem =~ /\.gem$/ ? gem : new_dep(gem, version)

        if internal_plugin?(name) || gem_installed?(gem, version)
          info "Plugin #{name} already installed"

          return false
        else
          spec = dep_installer.install(install_arg).find do |spec|
            spec.name == gem
          end
          Gem.clear_paths
          info "Plugin #{name} installed (version #{spec.version})"

          return true
        end
      end

      def load_plugin(name)
        Busser::Plugin.require!(Busser::Plugin.runner_plugin(name))
      end

      def run_postinstall(name)
        klass = Busser::Plugin.runner_class(::Thor::Util.camel_case(name))
        if klass.respond_to?(:run_postinstall)
          banner "Running postinstall for #{name} plugin"
          klass.run_postinstall
        end
      end

      def internal_plugin?(name)
        spec = Busser::Plugin.gem_from_path(Busser::Plugin.runner_plugin(name))
        spec && spec.name == "busser"
      end

      def gem_installed?(name, version)
        installed = Array(Gem::Specification.find_all_by_name(name, version))
        version = latest_version(name) if version.nil?

        installed.find { |spec| spec.version.to_s == version }
      end

      def latest_version(name)
        available_gems = dep_installer.find_gems_with_sources(new_dep(name))

        spec, source = if available_gems.respond_to?(:last)
          # DependencyInstaller sorts the results such that the last one is
          # always the one it considers best.
          spec_with_source = available_gems.last
          spec_with_source && spec_with_source
        else
          # Rubygems 2.0 returns a Gem::Available set, which is a
          # collection of AvailableSet::Tuple structs
          available_gems.pick_best!
          best_gem = available_gems.set.first
          best_gem && [best_gem.spec, best_gem.source]
        end

        spec && spec.version && spec.version.to_s
      end

      def silence_gem_ui!
        Gem::DefaultUserInteraction.ui = Gem::SilentUI.new
      end

      def dep_installer
        Gem::DependencyInstaller.new
      end

      def new_dep(name, version = nil)
        Gem::Dependency.new(name, version)
      end
    end
  end
end
