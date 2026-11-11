# Run from the PH-Composer checkout, Ruby 3.2.2, no real SketchUp.
require_relative "../../../../tests/test_helper"
require_relative "../../../../tests/support/assembly_assignment_fixtures"
require_relative "../../../../tests/support/library_provider_fixtures"

class EnvelopeAccessProbe < PhComposerTestCase
  include AssemblyAssignmentFixtures
  include LibraryProviderFixtures
  A = PhComposer::AgentAccess
  P = 'ph_composer'

  def setup
    super
    assignment_setup
    @executor = A::Executor.new(:tools => A::Tools::TABLE)
    issued = A::Tokens.issue(:capabilities => %w[read model_write setup export])
    @token = A::Tokens.snapshot.fetch(A::Tokens.digest(issued.fetch('token')))
  end

  def agent(tool, params)
    @executor.call(@token, tool, { 'session' => @session.id }.merge(params)).fetch('structuredContent')
  end

  def measure(name, params = {})
    api = API.query(:context => @context, :name => name, :params => params)
    mcp = agent('query', 'name' => name, 'params' => params)
    puts [name, params.keys.join(','), "api=#{api['code']}:#{JSON.generate(api).bytesize}", "mcp=#{mcp['code'] || mcp['status']}", mcp['message']].join(' | ')
    [api, mcp]
  end

  def test_unit_metadata
    points = [[0, 0, 0], [1000, 0, 0], [1000, 1000, 0], [0, 1000, 0]].map { |xyz| Geom::Point3d.new(*xyz) }
    face = Sketchup::Face.new(1001, {}, :points => points)
    @model.entities << Sketchup::Group.new(1000, Sketchup::Entities.new([face]))
    made = assignment_invoke("#{P}.zones.make", 'parent_path' => [], 'entity_ids' => [1000])
    assert_equal 'completed', made['status'], made.inspect
    assignment_classify(assignment_faces, 'face_type' => { 'mode' => 'set', 'value' => 'Wall' },
                                          'boundary_condition' => { 'mode' => 'set', 'value' => 'Outdoors' })
    host = assignment_faces.first.fetch('reference')
    type = assignment_invoke("#{P}.windows.types.create", 'values' => { 'name' => 'Synthetic placement' })
    assert_equal 'completed', type['status'], type.inspect
    placed = assignment_invoke("#{P}.windows.units.place", 'host' => host, 'type_id' => type.dig('value', 'id'),
                               'anchor' => 'sill_center', 'offsets' => { 'x_m' => 3.0, 'y_m' => 3.0 },
                               'user_data' => { 'synthetic' => 'x' * 30_000 })
    assert_equal 'committed', placed['effect'], placed.inspect
    id = placed.dig('value', 'unit_id')
    api, mcp = measure("#{P}.windows.units.list", 'limit' => 1, 'ids' => [id])
    assert_equal 'completed', api['status']
    assert_equal 'request.response_too_large', mcp['code']
    _api, mcp = measure("#{P}.windows.units.list", 'limit' => 1, 'ids' => [id], 'fields' => ['values'])
    assert_equal 'params.invalid', mcp['code']
    _api, mcp = measure("#{P}.windows.units.outlines", 'limit' => 1)
    assert_equal id, mcp.dig('value', 'units', 0, 'reference', 'unit_id')
  end

  def test_library_load_and_reads_with_warnings
    Dir.mktmpdir('phc-envelope-probe') do |dir|
      path = write_library(File.join(dir, 'warnings.json'), envelope([library_row] + Array.new(350, false)))
      PhComposer::Library::Setup.add_file(:id => 'warning_rows', :label => 'Synthetic', :path => path)
      params = { 'provider_id' => 'warning_rows', 'kind' => 'materials' }
      load = agent('setup', 'name' => "#{P}.library.load", 'params' => params)
      puts "#{P}.library.load | mcp=#{load['status']}:#{load['code']} | #{load['message']} | #{load['detail']}"
      assert_equal 'completed', load['status']
      assert_includes load.dig('detail', 'omitted'), 'value'
      %w[catalog in_file].each do |query|
        api, mcp = measure("#{P}.library.#{query}", params.merge('limit' => 1))
        assert_equal 350, api.dig('value', 'warnings').count { |warning| warning['code'] == 'library.row_required_invalid' }
        assert_equal 1, api.dig('value', 'rows').length
        assert_equal 'request.response_too_large', mcp['code']
      end
    end
  end

  def test_library_one_large_valid_row
    Dir.mktmpdir('phc-envelope-probe') do |dir|
      row = library_row.merge('notes' => 'z' * 30_000)
      path = write_library(File.join(dir, 'large-row.json'), envelope([row]))
      PhComposer::Library::Setup.add_file(:id => 'large_row', :label => 'Synthetic', :path => path)
      params = { 'provider_id' => 'large_row', 'kind' => 'materials' }
      load = agent('setup', 'name' => "#{P}.library.load", 'params' => params)
      assert_equal 'completed', load['status']
      %w[catalog in_file].each do |query|
        api, mcp = measure("#{P}.library.#{query}", params.merge('limit' => 1))
        assert_equal 30_000, api.dig('value', 'rows', 0, 'snapshot', 'notes').length
        assert_equal 'request.response_too_large', mcp['code']
      end
    end
  end

  def test_export_preflight_and_face_area
    assignment_zone(1000, 180)
    api = API.export_preflight(:context => @context)
    mcp = agent('export_preflight', {})
    puts ['export_preflight', "findings=#{api.dig('value', 'findings').length}", "api=#{api['code']}:#{JSON.generate(api).bytesize}", "mcp=#{mcp['code']}", mcp['message']].join(' | ')
    assert_equal 'request.response_too_large', mcp['code']
    _api, mcp = measure("#{P}.zones.faces.export_preflight")
    assert_equal 'request.response_too_large', mcp['code']
    _api, mcp = measure("#{P}.windows.units.glazed_area_by_face")
    assert_equal 'request.response_too_large', mcp['code']
    %W[#{P}.zones.faces.export_preflight #{P}.windows.units.glazed_area_by_face].each do |name|
      _api, mcp = measure(name, 'limit' => 1)
      assert_equal 'params.invalid', mcp['code']
    end
  end

  def test_large_host_holes
    outer = [[0, 0, 0], [1000, 0, 0], [1000, 1000, 0], [0, 1000, 0]].map { |xyz| Geom::Point3d.new(*xyz) }
    holes = Array.new(450) do |index|
      x = 25 + 30 * (index % 30)
      y = 25 + 30 * (index / 30)
      [[x, y, 0], [x, y + 10, 0], [x + 10, y + 10, 0], [x + 10, y, 0]].map { |xyz| Geom::Point3d.new(*xyz) }
    end
    face = Sketchup::Face.new(1001, {}, :points => outer, :holes => holes)
    @model.entities << Sketchup::Group.new(1000, Sketchup::Entities.new([face]))
    made = assignment_invoke("#{P}.zones.make", 'parent_path' => [], 'entity_ids' => [1000])
    assert_equal 'completed', made['status'], made.inspect
    ref = assignment_faces.first.fetch('reference')
    api, mcp = measure("#{P}.windows.units.host_extent", 'host' => ref, 'limit' => 1)
    assert_equal 450, api.dig('value', 'holes').length
    assert_equal 'request.response_too_large', mcp['code']
  end
end

class EnvelopeAccessProbe
  def test_window_type_children_do_not_fit_one_top_level_field
    rows = 10
    columns = 10
    elements = rows.times.flat_map do |row|
      columns.times.map do |column|
        index = row * columns + column
        PhComposer::Windows::Types.blank(row, column, :identity => ->(_prefix) { format('wel_%012d', index) })
      end
    end
    type = assignment_invoke("#{P}.windows.types.create", 'values' => {
      'name' => 'Synthetic gridded facade', 'rows_m' => [0.3] * rows, 'columns_m' => [0.3] * columns,
      'elements' => elements
    })
    assert_equal 'committed', type['effect'], type.inspect
    id = type.dig('value', 'id')
    %w[values display].each do |field|
      _api, mcp = measure("#{P}.windows.types.list", 'ids' => [id], 'limit' => 1, 'fields' => [field])
      assert_equal 'request.response_too_large', mcp['code']
    end
    _api, mcp = measure("#{P}.records.list", 'kind' => 'ph_composer.windows.window_type', 'ids' => [id],
                                          'limit' => 1, 'fields' => ['elements'])
    assert_equal 'request.response_too_large', mcp['code']
    _api, mcp = measure("#{P}.records.list", 'kind' => 'ph_composer.windows.window_type', 'ids' => [id],
                                          'limit' => 1, 'fields' => ['name'])
    assert_equal 'Synthetic gridded facade', mcp.dig('value', 'records', 0, 'values', 'name')
  end

  def test_generic_records_cannot_project_away_metadata
    action = assignment_invoke("#{P}.assemblies.materials.create", 'values' => { 'name' => 'Synthetic' },
                                                                   'user_data' => { 'large' => 'x' * 30_000 })
    assert_equal 'committed', action['effect'], action.inspect
    id = action.dig('value', 'id')
    _api, mcp = measure("#{P}.records.list", 'kind' => 'ph_composer.assemblies.material', 'ids' => [id],
                                          'limit' => 1, 'fields' => [])
    assert_equal 'request.response_too_large', mcp['code']
    _api, mcp = measure("#{P}.assemblies.materials.list", 'ids' => [id], 'limit' => 1, 'fields' => ['values'])
    assert_equal 'Synthetic', mcp.dig('value', 'records', 0, 'values', 'name')
  end

  def test_library_export_preview_omissions_can_block_the_replacement_digest
    kind = PhComposer::Assemblies::Materials::Schema::KIND
    180.times do |index|
      # Direct seed is test setup only, equivalent to ordinary create with metadata at a prior revision.
      values = PhComposer::Assemblies::Materials::Schema.defaults('name' => "Synthetic #{index}")
      kind.store.write(@model, values.merge('id' => format('mat_%012d', index), 'schema_version' => 1,
                                             'user_data' => { 'internal' => 'x' }))
    end
    Dir.mktmpdir('phc-envelope-probe') do |dir|
      path = write_library(File.join(dir, 'existing.json'))
      approved = PhComposer::ApprovedLocations.approve(:kind => 'save_file', :path => path)
      api, mcp = measure("#{P}.library.export_preview", 'location' => approved.fetch('id'))
      assert_equal 180, api.dig('value', 'omissions').length
      refute_nil api.dig('value', 'projection_digest')
      assert_equal 'request.response_too_large', mcp['code']
      _api, mcp = measure("#{P}.library.export_preview", 'location' => approved.fetch('id'), 'limit' => 1)
      assert_equal 'params.invalid', mcp['code']
    end
  end

  def test_oversized_blocked_task_is_missing_its_only_report_and_findings_over_mcp
    runtime = Class.new do
      def initialize(session_id:, on_message:)
        @on_message = on_message
      end
      def start; end
      def stop; end
      def translate(id, _document)
        findings = Array.new(240) do |index|
          { 'code' => 'object.unavailable', 'section' => 'synthetic', 'object_id' => "fixture_#{index}",
            'message' => 'A unique runtime finding from the synthetic blocked export.', 'blocks_export' => true }
        end
        result = { 'schema_version' => 1, 'run_id' => id, 'state' => 'complete_with_findings', 'sections' => [],
                   'failure' => nil, 'findings' => findings,
                   'summary' => { 'objects' => 0, 'unavailable' => findings.length, 'findings' => findings.length,
                                  'publishable' => false } }
        @on_message.call('runtime.translation', 'request_id' => id, 'result' => result)
      end
    end
    Dir.mktmpdir('phc-envelope-probe') do |dir|
      approved = PhComposer::ApprovedLocations.approve(:kind => 'save_file', :path => File.join(dir, 'test.hbjson'))
      task = PhComposer::RuntimeHost.stub(:new, ->(**args) { runtime.new(**args) }) do
        started = agent('start_export', 'location' => { 'id' => approved.fetch('id') })
        UI.run_timers
        started.fetch('value').fetch('task_id')
      end
      binding = A.bindings.fetch([@token.fetch('id'), @session.id]).context
      api = API.export_status(:context => binding, :task_id => task)
      assert_equal 240, api.dig('value', 'outcome', 'findings').length
      assert_includes api.dig('value', 'outcome', 'value', 'report_html'), 'A unique runtime finding'
      assert_empty Dir.children(dir)
      %w[export_status latest_export].each do |tool|
        mcp = agent(tool, tool == 'export_status' ? { 'task_id' => task } : {})
        puts "#{tool} | api=#{JSON.generate(api).bytesize}B/240 findings | mcp=#{mcp.dig('value', 'outcome', 'code')} | findings=#{mcp.dig('value', 'outcome', 'findings').inspect} | report=#{mcp.dig('value', 'outcome', 'value', 'report_html').inspect}"
        assert_equal 'export.blocked', mcp.dig('value', 'outcome', 'code')
        assert_nil mcp.dig('value', 'outcome', 'findings')
        assert_nil mcp.dig('value', 'outcome', 'value', 'report_html')
      end
    end
  end
end

class EnvelopeAccessProbe
  def test_assembly_reserved_metadata_block_is_absent_from_preflight
    created = assignment_invoke("#{P}.assemblies.assemblies.create", 'values' => { 'name' => 'Synthetic' },
                                                                  'user_data' => { 'ph_composer' => 'reserved' })
    assert_equal 'committed', created['effect'], created.inspect
    preflight = agent('export_preflight', {})
    refute_includes preflight.dig('value', 'findings').map { |row| row.fetch('code') }, 'export.blocked'
    Dir.mktmpdir('phc-envelope-probe') do |dir|
      approved = PhComposer::ApprovedLocations.approve(:kind => 'save_file', :path => File.join(dir, 'test.hbjson'))
      started = agent('start_export', 'location' => { 'id' => approved.fetch('id') })
      UI.run_timers
      outcome = agent('export_status', 'task_id' => started.dig('value', 'task_id')).dig('value', 'outcome')
      puts "assembly reserved user_data | export_preflight=#{preflight.dig('value', 'findings').map { |row| row.fetch('code') }} | task=#{outcome.values_at('status', 'code', 'message')}"
      assert_equal 'export.blocked', outcome['code']
      assert_includes outcome['message'], 'reserved key ph_composer'
      assert_empty Dir.children(dir)
    end
  end
end
