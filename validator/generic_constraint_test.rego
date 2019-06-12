package templates.gcp.GCPGenericConstraintV1

import data.test.fixtures.generic_constraint.assets as fixture_assets
import data.test.fixtures.generic_constraint.constraints as fixture_constraints

# Helper to lookup a constraint based on its name via metadata, not package
lookup_constraint[name] = [c] {
	c := fixture_constraints[_]
	c.metadata.name = name
}

lookup_constraint[name] = [c] {
	c := fixture_constraints[_][_]
	c.metadata.name = name
}

# Helper to execute constraints against assets
find_violations[violation] {
	asset := data.assets[_]
	constraint := data.test_constraints[_]
	issues := deny with input.asset as asset with input.constraint as constraint
	total_issues := count(issues)
	violation := issues[_]
}

# Helper to create a set of resource names from violations
resource_names[name] {
	# Not sure why I need this, data.violations was a array_set but unless
	# casted as an array all evals of X[_] would fail.  Tested iterating sets in
	# playground and they work fine, so I am not sure the problem here.
	a := cast_array(data.violations)
	i := a[_]
	trace(sprintf("Violations %v", [i]))
	name := i.details.resource
}

test_generic_overlapped_subnets {
	# Arrange
	expected_resources := {"//compute.googleapis.com/projects/sbx-5064-validator-te-36b9457b/regions/us-east1/subnetworks/subnet-2"}

	# Act
	found_violations := find_violations with data.assets as fixture_assets
		 with data.test_constraints as lookup_constraint.regional_subnets_must_be_overlapped

	found_resources := resource_names with data.violations as found_violations

	# Assert
	# opa eval -d=lib/ -d=validator/ --format=pretty --explain full "data.templates.gcp.GCPGenericConstraintV1.test_generic_overlapped_subnets"
trace(	sprintf("Found violations should be %v and got %v", [expected_resources, found_resources]))
	found_resources == expected_resources
}

test_bq_locations {
	# Arrange
	expected_resources := {"//bigquery.googleapis.com/projects/sandbox2/datasets/us_east4_test_dataset"}

	# Act
	found_violations := find_violations with data.assets as fixture_assets
		 with data.test_constraints as lookup_constraint.bq_dataset_location_allowlist_one_exemption

	found_resources := resource_names with data.violations as found_violations

	# Assert
	# opa eval -d=lib/ -d=validator/ --format=pretty --explain full "data.templates.gcp.GCPGenericConstraintV1.test_generic_overlapped_subnets"
trace(	sprintf("Found violations should be %v and got %v", [expected_resources, found_resources]))
	found_resources == expected_resources
}

test_logical_not_root {
	asset = {"foo": "bar", "name": "asset1", "asset_type": "test_asset"}
	test_cases := [
		{"input": {"rule": {"not": []}, "asset": asset}, "expected": {"has_rules": false, "result": false}},
		{
			"input": {
				"rule": {"not": [{"or": [
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
				]}]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": {
				"rule": {"not": [{"or": [
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
				]}]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": {
				"rule": {"not": [{"or": [
					{"and": [{"key": "foo", "value": "bar", "op": "eq", "type": "value"}, {"key": "foo", "value": "bar", "op": "eq", "type": "value"}]},
					{"and": [{"key": "foo", "value": "bar", "op": "eq", "type": "value"}, {"key": "foo", "value": "bar", "op": "ne", "type": "value"}]},
				]}]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": false},
		},
	]

	actuals := [r |
		#i := 3
		t := test_cases[i]
		output := eval_logical_not_l1 with data.rule as t.input.rule
			 with data.asset as t.input.asset

		r := {"actual": output, "i": i}
	]

	asserts := [r |
		a := actuals[_]
		r := test_cases[a.i].expected == a.actual
		trace(sprintf("Test Case %v, Actual: %v, Expected: %v", [a.i, a.actual, test_cases[a.i].expected]))
	]

	count(asserts) == count(test_cases)
	all(asserts)
}

test_logical_not_max_depth {
	asset = {"foo": "bar", "name": "asset1", "asset_type": "test_asset"}
	test_cases := [
		{"input": {"rule": {"not": []}, "asset": asset}, "expected": {"has_rules": false, "result": false}},
		{
			"input": {
				"rule": {"not": [
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
				]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": {
				"rule": {"not": [
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
				]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": {
				"rule": {"not": [
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
				]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": {
				"rule": {"not": [{"key": "foo", "value": "bar", "op": "eq", "type": "value"}]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": {
				"rule": {"not": [{"or": [{"key": "foo", "value": "bar", "op": "eq", "type": "value"}]}]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true, "error": true, "err_message": "Max expression depth reached"},
		},
	]

	actuals := [r |
		t := test_cases[i]
		output := eval_logical_not_l3 with data.rule as t.input.rule
			 with data.asset as t.input.asset

		r := {"actual": output, "i": i}
	]

	asserts := [r |
		a := actuals[_]
		r := test_cases[a.i].expected == a.actual
		trace(sprintf("Test Case %v, Actual: %v, Expected: %v", [a.i, a.actual, test_cases[a.i].expected]))
	]

	count(asserts) == count(test_cases)
	all(asserts)
}

test_logical_or_max_depth {
	asset = {"foo": "bar", "name": "asset1", "asset_type": "test_asset"}
	test_cases := [
		{"input": {"rule": {"or": []}, "asset": asset}, "expected": {"has_rules": false, "result": false}},
		{
			"input": {
				"rule": {"or": [
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
				]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": {
				"rule": {"or": [
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
				]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": {
				"rule": {"or": [
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
				]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": {
				"rule": {"or": [{"key": "foo", "value": "bar", "op": "eq", "type": "value"}]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": {
				"rule": {"or": [{"or": [{"key": "foo", "value": "bar", "op": "eq", "type": "value"}]}]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true, "error": true, "err_message": "Max expression depth reached"},
		},
	]

	actuals := [r |
		t := test_cases[i]
		output := eval_logical_or_l3 with data.rule as t.input.rule
			 with data.asset as t.input.asset

		r := {"actual": output, "i": i}
	]

	asserts := [r |
		a := actuals[_]
		r := test_cases[a.i].expected == a.actual
		trace(sprintf("Test Case %v, Actual: %v, Expected: %v", [a.i, a.actual, test_cases[a.i].expected]))
	]

	count(asserts) == count(test_cases)
	all(asserts)
}

test_logical_and_max_depth {
	asset = {"foo": "bar", "name": "asset1", "asset_type": "test_asset"}
	test_cases := [
		{"input": {"rule": {"and": []}, "asset": asset}, "expected": {"has_rules": false, "result": false}},
		{"input": {"rule": {"or": []}, "asset": asset}, "expected": {"has_rules": false, "result": false}},
		{"input": {"rule": {"not": []}, "asset": asset}, "expected": {"has_rules": false, "result": false}},
		{
			"input": {
				"rule": {"and": [
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
					{"key": "foo", "value": "bar", "op": "ne", "type": "value"},
				]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": {
				"rule": {"and": [
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
					{"key": "foo", "value": "bar", "op": "eq", "type": "value"},
				]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": {
				"rule": {"and": [{"key": "foo", "value": "bar", "op": "eq", "type": "value"}]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": {
				"rule": {"and": [{"or": [{"key": "foo", "value": "bar", "op": "eq", "type": "value"}]}]},
				"asset": asset,
			},
			"expected": {"has_rules": true, "result": true, "error": true, "err_message": "Max expression depth reached"},
		},
	]

	actuals := [r |
		t := test_cases[i]
		output := eval_logical_and_l3 with data.rule as t.input.rule
			 with data.asset as t.input.asset

		r := {"actual": output, "i": i}
	]

	asserts := [r | a := actuals[_]; r := test_cases[a.i].expected == a.actual]

	count(asserts) == count(test_cases)
	all(asserts)
}

test_aggregate_or_output {
	test_cases := [
		{
			"input": [{"has_rules": true, "result": true}],
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": [{"has_rules": true, "result": true}, {"has_rules": true, "result": false}],
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": [{"has_rules": false, "result": true}, {"has_rules": true, "result": false}],
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": [{"has_rules": true, "result": false}, {"has_rules": true, "result": false}],
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": [{"has_rules": false, "result": true}, {"has_rules": false, "result": false}],
			"expected": {"has_rules": false, "result": false},
		},
		{
			"input": [],
			"expected": {"has_rules": false, "result": false},
		},
	]

	actuals := [r | t := test_cases[i]; r := {"actual": aggregate_or_output(t.input), "i": i}]

	asserts := [r | a := actuals[_]; r := test_cases[a.i].expected == a.actual]

	count(asserts) == count(test_cases)
	all(asserts)
}

test_aggregate_and_output {
	test_cases := [
		{
			"input": [{"has_rules": true, "result": true}],
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": [{"has_rules": true, "result": true}, {"has_rules": true, "result": true}],
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": [{"has_rules": true, "result": true}, {"has_rules": true, "result": false}],
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": [{"has_rules": false, "result": true}, {"has_rules": true, "result": false}],
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": [{"has_rules": true, "result": false}, {"has_rules": true, "result": false}],
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": [{"has_rules": false, "result": true}, {"has_rules": false, "result": false}],
			"expected": {"has_rules": false, "result": false},
		},
		{
			"input": [],
			"expected": {"has_rules": false, "result": false},
		},
	]

	actuals := [r | t := test_cases[i]; r := {"actual": aggregate_and_output(t.input), "i": i}; trace(sprintf("Actual: %v, Expected: %v", [r.actual, t.expected]))]

	asserts := [r | a := actuals[_]; r := test_cases[a.i].expected == a.actual]

	count(asserts) == count(test_cases)
	all(asserts)
}

test_aggregate_not_output {
	test_cases := [
		{
			"input": [{"has_rules": true, "result": true}],
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": [{"has_rules": true, "result": true}, {"has_rules": true, "result": true}],
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": [{"has_rules": true, "result": true}, {"has_rules": true, "result": false}],
			"expected": {"has_rules": true, "result": false},
		},
		{
			"input": [{"has_rules": false, "result": true}, {"has_rules": true, "result": false}],
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": [{"has_rules": true, "result": false}, {"has_rules": true, "result": false}],
			"expected": {"has_rules": true, "result": true},
		},
		{
			"input": [{"has_rules": false, "result": true}, {"has_rules": false, "result": false}],
			"expected": {"has_rules": false, "result": false},
		},
		{
			"input": [],
			"expected": {"has_rules": false, "result": false},
		},
	]

	actuals := [r |
		t := test_cases[i]
		r := {
			"actual": aggregate_not_output(t.input),
			"i": i,
		}
		trace(sprintf("Test Case %v, Actual: %v, Expected: %v", [i, r.actual, t.expected]))
	]

	asserts := [r | a := actuals[_]; r := test_cases[a.i].expected == a.actual]
	count(asserts) == count(test_cases)
	all(asserts)
}
