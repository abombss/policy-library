#
# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

package templates.gcp.GCPGenericConstraintV1

import data.validator.gcp.lib as lib

############################################
# A Generic Tempalte Constraint similar to writing Cloud Custodian Filters
# https://cloudcustodian.io/docs/filters.html
############################################
deny[{
	"msg": message,
	"details": metadata,
}] {
	constraint := input.constraint
	lib.get_constraint_params(constraint, params)
	lib.get_constraint_info(constraint, info)

	asset := input.asset

	output := is_violation(asset, {"parameters": params, "name": info.name})
	output == true

	message := sprintf("%v did not pass filter.", [asset.name])
	metadata := {"resource": asset.name}
}

#################
# Rule Utilities
#################

# Helper function to evaluate an asset and a policy for violations
is_violation(asset, policy) = output {
	asset.asset_type == policy.parameters.asset_types[_]
	rules := policy.parameters.filters

	_trace_obj := {"policy": policy.name, "asset": asset.name, "asset_type": asset.asset_type}
	trace(sprintf("start is_violation: %v", [_trace_obj]))

	rule_output := eval_all_rules with data.rule as rules with data.asset as asset
	and_outputs := [o | o := eval_logical_and_l1 with data.rule as rules[_] with data.asset as asset]
	and_output := aggregate_and_output(and_outputs)
	or_outputs := [o | o := eval_logical_or_l1 with data.rule as rules[_] with data.asset as asset]
	or_output := aggregate_or_output(or_outputs)
	not_outputs := [o | o := eval_logical_not_l1 with data.rule as rules[_] with data.asset as asset]
	not_output := aggregate_and_output(not_outputs)

	agg_output := aggregate_or_output([rule_output, and_output, or_output, not_output])
	output := agg_output.result
	trace(sprintf("stop is_violation: [%v, %v]", [_trace_obj, output]))
}

# Constant reused for no-op results
no_op_output = {"result": false, "has_rules": false}

# Evaluates OR expressions for Level 1
eval_logical_or_l1 = output {
	rules := data.rule.or
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_or_l1: [%v]", [_trace_obj]))

	rule_output := eval_any_rules with data.rule as rules with data.asset as asset
	and_outputs := [o | o := eval_logical_and_l2 with data.rule as rules[_] with data.asset as asset]
	and_output := aggregate_or_output(and_outputs)
	or_outputs := [o | o := eval_logical_or_l2 with data.rule as rules[_] with data.asset as asset]
	or_output := aggregate_or_output(or_outputs)
	not_outputs := [o | o := eval_logical_not_l2 with data.rule as rules[_] with data.asset as asset]
	not_output := aggregate_or_output(not_outputs)

	output := aggregate_or_output([rule_output, and_output, or_output, not_output])

	trace(sprintf("stop eval_logical_or_l1: [%v, %v]", [_trace_obj, output]))
}

# Evaluates OR expressions for Level 1, handles the no-op case
eval_logical_or_l1 = output {
	not data.rule.or
	output := no_op_output
}

# Evaluates OR expressions for Level 2
eval_logical_or_l2 = output {
	rules := data.rule.or
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_or_l2: [%v]", [_trace_obj]))

	rule_output := eval_any_rules with data.rule as rules with data.asset as asset
	and_outputs := [o | o := eval_logical_and_l3 with data.rule as rules[_] with data.asset as asset]
	and_output := aggregate_or_output(and_outputs)
	or_outputs := [o | o := eval_logical_or_l3 with data.rule as rules[_] with data.asset as asset]
	or_output := aggregate_or_output(or_outputs)
	not_outputs := [o | o := eval_logical_not_l3 with data.rule as rules[_] with data.asset as asset]
	not_output := aggregate_or_output(not_outputs)

	output := aggregate_or_output([rule_output, and_output, or_output, not_output])

	trace(sprintf("stop eval_logical_or_l2: [%v, %v]", [_trace_obj, output]))
}

# Evaluates OR expressions for Level 2, handles the no-op case
eval_logical_or_l2 = output {
	not data.rule.or
	output := no_op_output
}

# Evaluates OR expressions for Level 3
eval_logical_or_l3 = output {
	rules := data.rule.or
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_or_l3: [%v]", [_trace_obj]))

	assert_no_nested_ops(rules)

	output := eval_any_rules with data.rule as rules with data.asset as asset
	trace(sprintf("stop eval_logical_or_l3: [%v, %v]", [_trace_obj, output]))
}

# TODO: Error Handling for max logical depth

# Evaluates OR expressions for Level 3, handles an error condition where we have
# reached max depth.
eval_logical_or_l3 = output {
	rules := data.rule.or
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_or_l3-MAX_DEPTH: [%v]", [_trace_obj]))

	assert_has_nested_ops(rules)

	output := {
		"has_rules": true,
		"result": true,
		"error": true,
		"err_message": "Max expression depth reached",
	}

	trace(sprintf("stop eval_logical_or_l3-MAX_DEPTH: [%v, %v]", [_trace_obj, output]))
}

# Evaluates OR expressions for Level 3, handles the no-op case
eval_logical_or_l3 = output {
	not data.rule.or
	output := no_op_output
}

# True if rules contains no nested operations, otherwise false
assert_no_nested_ops(rules) = output {
	m := [r | v := ["or", "not", "and"]; r := rules[_]; k := v[_]; r[k]]
	output := count(m) == 0
}

# True if rules contains nested operations, otherwise false
assert_has_nested_ops(rules) = output {
	m := [r | v := ["or", "not", "and"]; r := rules[_]; k := v[_]; r[k]]
	output := count(m) > 0
}

eval_logical_not_l3 = output {
	rules := data.rule["not"]
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_not_l3: [%v]", [_trace_obj]))

	assert_no_nested_ops(rules)

	o := eval_all_rules with data.rule as rules with data.asset as asset
	lookup_output := [{"has_rules": false, "output": no_op_output}, {"has_rules": true, "output": {"has_rules": true, "result": negate(o.result)}}]
	outputs := [r | lk := lookup_output[_]; lk.has_rules = o.has_rules; r := lk.output]

	# count(outputs) == 1 # Debug Assertion
	output := outputs[0]

	trace(sprintf("stop eval_logical_not_l3: [%v, %v]", [_trace_obj, output]))
}

eval_logical_not_l3 = output {
	rules := data.rule["not"]
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_not_l3-MAX_DEPTH: [%v]", [_trace_obj]))

	assert_has_nested_ops(rules)

	output := {
		"has_rules": true,
		"result": true,
		"error": true,
		"err_message": "Max expression depth reached",
	}

	trace(sprintf("stop eval_logical_not_l3-MAX_DEPTH: [%v, %v]", [_trace_obj, output]))
}

eval_logical_not_l3 = output {
	not data.rule["not"]
	output := no_op_output
}

eval_logical_and_l3 = output {
	rules := data.rule.and
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_and_l3: [%v]", [_trace_obj]))

	assert_no_nested_ops(rules)

	output := eval_all_rules with data.rule as rules with data.asset as asset
	trace(sprintf("stop eval_logical_and_l3: [%v, %v]", [_trace_obj, output]))
}

eval_logical_and_l3 = output {
	rules := data.rule.and
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_and_l3-MAX_DEPTH: [%v]", [_trace_obj]))

	assert_has_nested_ops(rules)

	output := {
		"has_rules": true,
		"result": true,
		"error": true,
		"err_message": "Max expression depth reached",
	}

	trace(sprintf("stop eval_logical_and_l3-MAX_DEPTH: [%v, %v]", [_trace_obj, output]))
}

eval_logical_and_l3 = output {
	not data.rule.and
	output := no_op_output
}

eval_logical_not_l1 = output {
	rules := data.rule["not"]
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_not_l1: [%v]", [_trace_obj]))

	rule_output := eval_all_rules with data.rule as rules with data.asset as asset
	and_outputs := [o | o := eval_logical_and_l2 with data.rule as rules[_] with data.asset as asset]
	and_output := aggregate_and_output(and_outputs)
	or_outputs := [o | o := eval_logical_or_l2 with data.rule as rules[_] with data.asset as asset]
	or_output := aggregate_and_output(or_outputs)
	not_outputs := [o | o := eval_logical_not_l2 with data.rule as rules[_] with data.asset as asset]
	not_output := aggregate_and_output(not_outputs)

	output := aggregate_not_output([rule_output, and_output, or_output, not_output])

	trace(sprintf("stop eval_logical_not_l1: [%v, %v]", [_trace_obj, output]))
}

eval_logical_not_l1 = output {
	not data.rule["not"]
	output := no_op_output
}

eval_logical_not_l2 = output {
	rules := data.rule["not"]
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_not_l2: [%v]", [_trace_obj]))

	rule_output := eval_all_rules with data.rule as rules with data.asset as asset
	and_outputs := [o | o := eval_logical_and_l3 with data.rule as rules[_] with data.asset as asset]
	and_output := aggregate_and_output(and_outputs)
	or_outputs := [o | o := eval_logical_or_l3 with data.rule as rules[_] with data.asset as asset]
	or_output := aggregate_and_output(or_outputs)
	not_outputs := [o | o := eval_logical_not_l3 with data.rule as rules[_] with data.asset as asset]
	not_output := aggregate_and_output(not_outputs)

	output := aggregate_not_output([rule_output, and_output, or_output, not_output])

	trace(sprintf("stop eval_logical_not_l2: [%v, %v]", [_trace_obj, output]))
}

eval_logical_not_l2 = output {
	not data.rule["not"]
	output := no_op_output
}

# Helpers for the NOT expression, is there an easier to flip a boolean in rego?
negate(value) = false {
	value == true
}

negate(value) {
	value == false
}

eval_logical_and_l1 = output {
	rules := data.rule.and
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_and_l1: [%v]", [_trace_obj]))

	rule_output := eval_all_rules with data.rule as rules with data.asset as asset
	and_outputs := [o | o := eval_logical_and_l2 with data.rule as rules[_] with data.asset as asset]
	and_output := aggregate_and_output(and_outputs)
	or_outputs := [o | o := eval_logical_or_l2 with data.rule as rules[_] with data.asset as asset]
	or_output := aggregate_and_output(or_outputs)
	not_outputs := [o | o := eval_logical_not_l2 with data.rule as rules[_] with data.asset as asset]
	not_output := aggregate_and_output(not_outputs)

	output := aggregate_and_output([rule_output, or_output, and_output, not_output])

	trace(sprintf("stop eval_logical_and_l1: [%v, %v]", [_trace_obj, output]))
}

aggregate_and_output(outputs) = output {
	_trace_obj := {} #{ "asset": data.asset.name, "rule": data.rule }
	results := [result | r := outputs[_]; r.has_rules; result := r.result; trace(sprintf("aggregate_and_output__item: %v results are: %v", [_trace_obj, r]))]
	has_rules := count(results) > 0
	results_override := array.concat(results, [has_rules])
	output := {"has_rules": has_rules, "result": all(results_override)}
	trace(sprintf("aggregate_and_output: %v results are: %v", [_trace_obj, output]))
}

aggregate_or_output(outputs) = output {
	_trace_obj := {} #{ "asset": data.asset.name, "rule": data.rule }
	results := [result | r := outputs[_]; r.has_rules; result := r.result; trace(sprintf("aggregate_or_output__item: %v results are: %v", [_trace_obj, r]))]
	output := {"has_rules": count(results) > 0, "result": any(results)}
	trace(sprintf("aggregate_or_output: %v results are: %v", [_trace_obj, output]))
}

aggregate_not_output(outputs) = output {
	_trace_obj := {} #{ "asset": data.asset.name, "rule": data.rule }
	results := [result | r := outputs[_]; r.has_rules; result := negate(r.result); trace(sprintf("aggregate_not_output__item: %v results are: %v", [_trace_obj, r]))]
	has_rules := count(results) > 0
	results_override := array.concat(results, [has_rules])
	output := {"has_rules": has_rules, "result": all(results_override)}
	trace(sprintf("aggregate_not_output: %v results are: %v", [_trace_obj, output]))
}

eval_logical_and_l1 = output {
	not data.rule.and
	output := no_op_output
}

eval_logical_and_l2 = output {
	rules := data.rule.and
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": rules}
	trace(sprintf("start eval_logical_and_l2: [%v]", [_trace_obj]))

	rule_output := eval_all_rules with data.rule as rules with data.asset as asset
	and_outputs := [o | o := eval_logical_and_l3 with data.rule as rules[_] with data.asset as asset]
	and_output := aggregate_and_output(and_outputs)
	or_outputs := [o | o := eval_logical_or_l3 with data.rule as rules[_] with data.asset as asset]
	or_output := aggregate_and_output(or_outputs)
	not_outputs := [o | o := eval_logical_not_l3 with data.rule as rules[_] with data.asset as asset]
	not_output := aggregate_and_output(not_outputs)

	output := aggregate_and_output([rule_output, or_output, and_output, not_output])

	trace(sprintf("stop eval_logical_and_l2: [%v, %v]", [_trace_obj, output]))
}

eval_logical_and_l2 = output {
	not data.rule.and
	output := no_op_output
}

# Root helper to evaluate all the leaf rules, not nested expressions
# Uses AND like logic where ALL rules must evaluate to true to return a true result
eval_all_rules = output {
	filters := data.rule
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": filters}
	trace(sprintf("start eval_all_rules: [%v]", [_trace_obj]))

	all_rule_output := [rule_output | rule := filters[_]; not rule.or; not rule.and; not rule["not"]; rule_output := eval_rule with data.rule as rule with data.asset as asset]

	# if there are any rules, then they all must be true in order to violate
	output := {"result": all(array.concat(all_rule_output, [count(all_rule_output) > 0])), "has_rules": count(all_rule_output) > 0}
	trace(sprintf("stop eval_all_rules: [%v, %v]", [_trace_obj, output]))
}

# Root helper to evaluate all the leaf rules, not nested expressions
# Uses OR like logic where ANY rule must evaluate to true to return a true result
eval_any_rules = output {
	filters := data.rule
	asset := data.asset

	_trace_obj := {"asset": asset.name, "asset_type": asset.asset_type, "rules": filters}
	trace(sprintf("start eval_any_rules: [%v]", [_trace_obj]))

	all_rule_output := [rule_output |
		rule := filters[_]
		not rule.or
		not rule.and
		not rule["not"]
		trace(sprintf("start eval_any_rules:eval_rule [%v, %v]", [_trace_obj.asset, rule]))
		rule_output := eval_rule with data.rule as rule
			 with data.asset as asset

		trace(sprintf("stop eval_any_rules:eval_rule [%v, %v,%v]", [_trace_obj.asset, rule, rule_output]))
	]

	# if there are any rules, then one must be true in order to violate
	output := {
		"result": all({any(all_rule_output)} | {count(all_rule_output) > 0}),
		"has_rules": count(all_rule_output) > 0,
	}

	trace(sprintf("stop eval_any_rules: [%v, %v]", [_trace_obj, output]))
}

#output := all( {any(all_rule_output)} | {count(all_rule_output) > 0} )

# Evaluates a single rule, handles the no-op case
eval_rule = false {
	not data.rule.key
}

# Evaluates a single rule
eval_rule = output {
	key := data.rule.key

	# Capture the value projection here so it can be reused as much as possible by
	# downstream rule evaluators
	field_value := get_field_by_path(data.asset, key)

	_trace_obj := {"rule": data.rule, "field_value": field_value, "asset": data.asset.name}
	trace(sprintf("start eval_rule: [%v]", [_trace_obj]))

	rule_type_result := eval_rule_type with data.field_value as field_value

	# Previously I used mode for "allow" and "deny" behavior at the rule Level
	# which made boolean logic backwards (Allow returns a false since we won't
	# deny that rule), but when combined with OR and NOT it required to flip the
	# rule to deny to get the desired behavior.  I think we keep ALL rules as simple
	# INCLUDES and use the NOT to exlude if desired.
	output := mode_to_output(get_default_by_path(data.rule, "mode", "allow"), rule_type_result)

	trace(sprintf("stop eval_rule: [%v, %v]", [_trace_obj, output]))
}

eval_rule_type = output {
	data.rule.type == "regex"
	output := re_match(concat("", ["(?i)", data.rule.value]), data.field_value)
}

eval_rule_type = output {
	data.rule.type == "regex-case"
	output := re_match(data.rule.value, data.field_value)
}

ops_eq = ["equal", "eq"]

eval_rule_type = output {
	data.rule.type == "value"
	data.rule.op = ops_eq[_]
	field_value := data.field_value
	output := data.rule.value == field_value
}

ops_ne = ["not-equal", "ne"]

eval_rule_type = output {
	data.rule.type == "value"
	data.rule.op = ops_ne[_]
	field_value := data.field_value
	output := data.rule.value != field_value
}

ops_gt = ["greater-than", "gt"]

eval_rule_type = output {
	data.rule.type == "value"
	data.rule.op = ops_gt[_]
	field_value := data.field_value
	output := data.rule.value > field_value
}

ops_gte = ["gte", "ge"]

eval_rule_type = output {
	data.rule.type == "value"
	data.rule.op = ops_gte[_]
	field_value := data.field_value
	output := data.rule.value >= field_value
}

ops_lt = ["less-than", "lt"]

eval_rule_type = output {
	data.rule.type == "value"
	data.rule.op = ops_lt[_]
	field_value := data.field_value
	output := data.rule.value < field_value
}

ops_lte = ["lte", "le"]

eval_rule_type = output {
	data.rule.type == "value"
	data.rule.op = ops_lte[_]
	field_value := data.field_value
	output := data.rule.value <= field_value
}

eval_rule_type = output {
	data.rule.type == "value"
	not data.rule.op
	data.rule.value == "present"
	output := has_field_by_path(data.asset, data.rule.key)
}

eval_rule_type = output {
	data.rule.type == "value"
	not data.rule.op
	data.rule.value == "absent"
	output := has_field_by_path(data.asset, data.rule.key) == false
}

eval_rule_type = output {
	data.rule.type == "value"
	not data.rule.op
	data.rule.value == "null"
	output := data.field_value == null
}

eval_rule_type = output {
	data.rule.type == "value"
	not data.rule.op
	data.rule.value == "not-null"
	output := data.field_value != null
}

# This seems to mess with a lot of logic on the OR and AND side
# I think we remove the concept of allow / deny
# assume everything is a "match" and let the user use a
# 'not' if they need to negate the result
# it was previously flipped where allow returned false since validator uses deny
#
mode_to_output(mode, is_valid) = output {
	results = {
		["allow", true, true],
		["allow", false, false],
		["deny", true, false],
		["deny", false, true],
	}

	results[[mode, is_valid, output]]
}

# TODO: Work on something way more robust including
# support for projections
get_field_by_path(obj, path) = output {
	split(path, ".", path_parts)
	walk(obj, [path_parts, output])
}

# wrapper around walk to explicitly capture the output in order to generate a
# true / false output instead of undefined.
# see: https://openpolicyagent.slack.com/messages/C1H19LW4F/convo/C1H19LW4F-1552948594.244300/
_has_field_by_path(obj, path) {
	_ := get_field_by_path(obj, path)
}

has_field_by_path(obj, path) {
	_has_field_by_path(obj, path)
}

has_field_by_path(obj, path) = false {
	not _has_field_by_path(obj, path)
}

get_default_by_path(obj, path, _default) = output {
	has_field_by_path(obj, path)
	output := get_field_by_path(obj, path)
}

get_default_by_path(obj, path, _default) = output {
	false == has_field_by_path(obj, path)
	output := _default
}
