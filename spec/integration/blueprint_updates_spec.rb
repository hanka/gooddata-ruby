# encoding: UTF-8
#
# Copyright (c) 2010-2017 GoodData Corporation. All rights reserved.
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

require 'gooddata'

describe 'Create project using GoodData client - blueprint', :vcr, :constraint => 'slow' do
  before(:all) do
    @client = ConnectionHelper.create_default_connection
    @blueprint = GoodData::Model::ProjectBlueprint.from_json('./spec/data/blueprints/test_project_model_spec.json')
    @project = @client.create_project_from_blueprint(@blueprint, auth_token: ConnectionHelper::SECRETS[:gd_project_token], environment: ProjectHelper::ENVIRONMENT)
  end

  after(:all) do
    @project.delete
    @client.disconnect
  end

  it 'Should create project using GoodData::Rest::Client#create_project' do
    data = [
      %w(repo_id repo_name),
      [1, "goodot"],
      [2, "bam"],
      [3, "infra"]
    ]
    @project.upload(data, @blueprint, 'dataset.repos')

    data = [
      %w(dev_id email),
      ['1', 'tomas@gmail.com'],
      ['2', 'petr@gmail.com'],
      ['3', 'jirka@gmail.com']
    ]
    @project.upload(data, @blueprint, 'dataset.devs')

    data = [
      %w(lines_changed committed_on dev_id repo_id),
      [1, '01/01/2011', '1', '1'],
      [2, '01/01/2011', '2', '2'],
      [3, '01/01/2011', '3', '3']
    ]
    @project.upload(data, @blueprint, 'dataset.commits')
  end

  it "should be able to add anchor's labels" do
    bp = @project.blueprint
    bp.datasets('dataset.commits').change do |d|
      d.add_label(
        'label.commits.factsof.id',
        reference: 'attr.commits.factsof',
        name: 'anchor_label'
      )
    end
    @project.update_from_blueprint(bp, maql_replacements: { "PRESERVE DATA" => "" })
    data = [
      ['label.commits.factsof.id', 'fact.commits.lines_changed', 'committed_on', 'dataset.devs', 'dataset.repos'],
      ['111', 1, '01/01/2011', '1', '1'],
      ['222', 2, '01/01/2011', '2', '2'],
      ['333', 3, '01/01/2011', '3', '3']
    ]
    @project.upload(data, bp, 'dataset.commits')
    m = @project.facts.first.create_metric
    @project.compute_report(top: [m], left: ['label.commits.factsof.id'])
  end

  it "be able to remove anchor's labels" do
    bp = @project.blueprint
    bp.datasets('dataset.commits').anchor.strip!
    @project.update_from_blueprint(bp)
    bp = @project.blueprint
    expect(bp.datasets('dataset.commits').anchor.labels.count).to eq 0
    expect(@project.labels('label.commits.factsof.id')).to eq nil
  end

  it "is possible to move attribute. Let's make a fast attribute." do
    # define stuff
    m = @project.facts.first.create_metric.save
    report = @project.create_report(title: 'Test report', top: [m], left: ['label.devs.dev_id.email'])
    # both compute
    expect(m.execute).to eq 6
    expect(report.execute.without_top_headers.to_a).to eq [['jirka@gmail.com', 3],
                                                           ['petr@gmail.com', 2],
                                                           ['tomas@gmail.com', 1]]

    # We move attribute
    @blueprint.move!('some_attr_id', 'dataset.repos', 'dataset.commits')
    @project.update_from_blueprint(@blueprint)

    # load new data
    data = [
      %w(lines_changed committed_on dev_id repo_id repo_name),
      [1, '01/01/2011', '1', '1', 'goodot'],
      [2, '01/01/2011', '2', '2', 'goodot'],
      [3, '01/01/2011', '3', '3', 'infra']
    ]
    @project.upload(data, @blueprint, 'dataset.commits')

    # both still compute
    # since we did not change the grain the results are the same
    expect(m.execute).to eq 6
    expect(report.execute.without_top_headers.to_a).to eq [["jirka@gmail.com", 3],
                                                           ["petr@gmail.com", 2],
                                                           ["tomas@gmail.com", 1]]
    # return atribute back where it came from
    @blueprint.move!('some_attr_id', 'dataset.commits', 'dataset.repos')
    @project.update_from_blueprint(@blueprint)
  end

  context 'when working with column mapping' do
    let(:data) do
      [
        %w[lines date developer repository],
        [1, '01/01/2011', '1', '1'],
        [2, '01/01/2011', '2', '2'],
        [3, '01/01/2011', '3', '3']
      ]
    end
    let(:column_mapping) do
      {
        lines_changed: 'lines',
        committed_on: 'date',
        dev_id: 'developer',
        repo_id: 'repository'
      }
    end

    it 'uploads data correctly' do
      @project.upload(data, @blueprint, 'dataset.commits', column_mapping: column_mapping)
    end

    it 'uploads data correctly from a file' do
      begin
        file = Tempfile.new
        data.each do |row|
          file.write row.to_csv
        end
        file.close

        @project.upload(file.path, @blueprint, 'dataset.commits', column_mapping: column_mapping)
      ensure
        file.delete if file
      end
    end

    it 'fails with a human readable output when column_mapping is not correct' do
      wrong_column_mapping = column_mapping.tap { |c| c[:lines_changed] = 'wrong_one' }
      expect { @project.upload(data, @blueprint, 'dataset.commits', column_mapping: wrong_column_mapping) }.to raise_exception(/lines_changed/)
    end

    it 'works with #upload_multiple' do
      @project.upload_multiple(
        [{
          data: data,
          dataset: 'dataset.commits',
          options: {
            column_mapping: column_mapping
          }
        }],
        @blueprint
      )
    end
  end
end
