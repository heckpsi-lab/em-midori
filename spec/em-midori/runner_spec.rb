require './spec/spec_helper'

RSpec.describe Midori::Runner do
  describe 'Runner with default configure' do
    subject { Midori::Runner.new(ExampleAPI, ExampleConfigure) }

    after {
      subject.stop
      sleep 10
    }

    it 'should not stop before started' do
      expect(subject.stop).to eq(false)
    end

    it 'should start properly' do
      expect do
        Thread.new { subject.start }
        sleep 5
      end.to_not raise_error(RuntimeError)
    end
  end

  describe 'Running runner' do
    subject { Midori::Runner.new(ExampleAPI, ExampleConfigure) }

    before do
      Thread.new { subject.start }
      sleep 5
    end

    it 'should stop properly' do
      expect(subject.stop).to eq(true)
      sleep(1)
    end

    it 'should not receive anything after stopped' do
      expect do
        subject.stop
        sleep 5
        puts Net::HTTP.get(URI('http://127.0.0.1:8080/'))
        Net::HTTP.get(URI('http://127.0.0.1:8080/'))
      end.to raise_error(Errno::ECONNREFUSED)
    end
  end
end
