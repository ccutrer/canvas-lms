#
# Copyright (C) 2015 Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.
#

require File.expand_path(File.dirname(__FILE__) + '/../../spec_helper.rb')

describe AccountAuthorizationConfig::OpenIDConnect do
  describe "#user_logout_url" do
    it "returns the end_session_endpoint" do
      ap = AccountAuthorizationConfig::OpenIDConnect.new(end_session_endpoint: "http://somewhere/logout")
      expect(ap.user_logout_redirect(nil, nil)).to eq "http://somewhere/logout"
    end
  end
end
