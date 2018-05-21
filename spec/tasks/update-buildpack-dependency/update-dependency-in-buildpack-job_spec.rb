# encoding: utf-8
require 'spec_helper'
require_relative '../../../tasks/update-buildpack-dependency/dependencies'

describe Dependencies do
  subject { described_class.new(dep, line, keep_master, dependencies, master_dependencies).switch }
  let(:dependencies) {
    ['stack1', 'stack2'].map do |stack|
      [
        { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => stack },
        { 'name' => 'ruby', 'version' =>  '1.2.3', 'stack' => stack },
        { 'name' => 'ruby', 'version' =>  '1.2.4', 'stack' => stack },
        { 'name' => 'ruby', 'version' =>  '1.3.4', 'stack' => stack },
        { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => stack },
        { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => stack }
      ]
    end.flatten.freeze
  }
  let(:master_dependencies) {
    ['stack1', 'stack2'].map do |stack|
      [
        { 'name' => 'bundler', 'version' =>  '1.2.1', 'stack' => stack },
        { 'name' => 'ruby', 'version' =>  '1.2.2', 'stack' => stack },
        { 'name' => 'ruby', 'version' =>  '1.2.3', 'stack' => stack },
        { 'name' => 'ruby', 'version' =>  '2.3.1', 'stack' => stack },
        { 'name' => 'ruby', 'version' =>  '2.3.2', 'stack' => stack }
      ]
    end.flatten.freeze
  }

  context 'keep_master is true'  do
    let(:line) { 'major' }
    let(:keep_master) { 'true' }

    context 'new version is newer than all existing on its line' do
      let(:dep) { { 'name' => 'ruby', 'version' => '1.4.0', 'stack' => 'stack1' } }

      it 'replaces all of the named dependencies on its line with the same stack keeping the latest from master' do
        expect(subject).to eq([
          { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack1' },
          { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack2' },
          { 'name' => 'ruby', 'version' =>  '1.2.3', 'stack' => 'stack1' },
          { 'name' => 'ruby', 'version' =>  '1.2.3', 'stack' => 'stack2' },
          { 'name' => 'ruby', 'version' =>  '1.2.4', 'stack' => 'stack2' },
          { 'name' => 'ruby', 'version' =>  '1.3.4', 'stack' => 'stack2' },
          { 'name' => 'ruby', 'version' =>  '1.4.0', 'stack' => 'stack1' },
          { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => 'stack1' },
          { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => 'stack2' },
          { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => 'stack1' },
          { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => 'stack2' }
        ])
      end
    end
  end

  context 'keep_master is nil' do
    context 'no version line specified' do
      let(:line) { nil }
      let(:keep_master) { nil }

      context 'new version is newer than all existing' do
        let(:dep) { { 'name' => 'ruby', 'version' => '3.0.0', 'stack' => 'stack1'} }
        it 'replaces all of the named dependencies with the same stack' do
          expect(subject).to eq([
            { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack1' },
            { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.2.3', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.2.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.3.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '3.0.0', 'stack' => 'stack1' }
          ])
        end
      end
      context 'new version is the same as an existing version but with different stack' do
        let(:dep) { { 'name' => 'ruby', 'version' => '1.3.4', 'stack' => 'stack3' } }

        it 'keeps the existing versions of the same name' do
          expect(subject).to eq([
            { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack1' },
            { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.2.3', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '1.2.3', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.2.4', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '1.2.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.3.4', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '1.3.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.3.4', 'stack' => 'stack3' },
            { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => 'stack2' }
          ])
        end
      end
      context 'new version is older than any existing' do
        let(:dep) { { 'name' => 'ruby', 'version' => '2.0.0', 'stack' => 'stack1' } }
        it 'returns unchanged dependencies' do
          expect(subject).to eq(dependencies)
        end
      end
    end

    context 'version line is major' do
      let(:line) { "major" }
      let(:keep_master) { nil }

      context 'new version is newer than all existing on its line' do
        let(:dep) { { 'name' => 'ruby', 'version' => '1.4.0', 'stack' => 'stack1' } }

        it 'replaces all of the named dependencies on its line with the same stack' do
          expect(subject).to eq([
            { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack1' },
            { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.2.3', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.2.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.3.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.4.0', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => 'stack2' }
          ])
        end
      end
      context 'new version is part of a new line' do
        let(:dep) { { 'name' => 'ruby', 'version' => '3.0.0', 'stack' => 'stack1' } }
        it 'Maintains all old dependencies and adds the new one' do
          expected_dependencies = dependencies.sort_by do |d|
            version = Gem::Version.new(d['version']) rescue d['version']
            [ d['name'], version, d['stack'] ]
          end
          expect(subject).to eq(expected_dependencies + [
            { 'name' => 'ruby', 'version' =>  '3.0.0', 'stack' => 'stack1' }
          ])
        end
      end
      context 'new version is older than any existing on its line' do
        let(:dep) { { 'name' => 'ruby', 'version' => '2.3.5', 'stack' => 'stack1' } }
        it 'returns unchanged dependencies' do
          expect(subject).to eq(dependencies)
        end
      end
    end
    context 'version line is minor' do
      let(:line) { "minor" }
      let(:keep_master) { nil }

      context 'new version is newer than all existing on its line' do
        let(:dep) { { 'name' => 'ruby', 'version' => '1.2.5', 'stack' => 'stack1' } }

        it 'replaces all of the named dependencies on its line' do
          expect(subject).to eq([
            { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack1' },
            { 'name' => 'bundler', 'version' =>  '1.2.3', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.2.3', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.2.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '1.2.5', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '1.3.4', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '1.3.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '2.3.4', 'stack' => 'stack2' },
            { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => 'stack1' },
            { 'name' => 'ruby', 'version' =>  '2.3.6', 'stack' => 'stack2' }
          ])
        end
      end
      context 'new version is part of a new line' do
        let(:dep) { { 'name' => 'ruby', 'version' => '2.4.0', 'stack' => 'stack1' } }
        it 'Maintains all old dependencies and adds the new one' do
          expected_dependencies = dependencies.sort_by do |d|
            version = Gem::Version.new(d['version']) rescue d['version']
            [ d['name'], version, d['stack'] ]
          end
          expect(subject).to eq(expected_dependencies + [
            { 'name' => 'ruby', 'version' =>  '2.4.0', 'stack' => 'stack1' }
          ])
        end
      end
      context 'new version is older than any existing on its line' do
        let(:dep) { { 'name' => 'ruby', 'version' => '2.3.5', 'stack' => 'stack1' } }
        it 'returns unchanged dependencies' do
          expect(subject).to eq(dependencies)
        end
      end
    end
  end
end
