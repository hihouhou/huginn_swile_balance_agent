require 'rails_helper'
require 'huginn_agent/spec_helper'

describe Agents::SwileBalanceAgent do
  before(:each) do
    @valid_options = Agents::SwileBalanceAgent.new.default_options
    @checker = Agents::SwileBalanceAgent.new(:name => "SwileBalanceAgent", :options => @valid_options)
    @checker.user = users(:bob)
    @checker.save!
  end

  pending "add specs here"
end
