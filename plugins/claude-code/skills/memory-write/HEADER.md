# Skill: Memory Writer (`memory_write`)

## Purpose

This skill defines how the model MUST use the `memory_write` tool to store user-relevant signals.

The goal is to capture **structured episodic events** that will later be processed by the external hippocampal memory system.

## Core Principle

> Only store what is likely to matter beyond the current conversation turn.

If uncertain, DO NOT write to memory. For privacy and safety constraints, follow the **memory-policy** skill.

## System Boundary Rule

This skill does NOT:
- create EMUs
- perform clustering
- summarize memory
- infer long-term patterns
- modify stored memory structure

It ONLY emits raw episodic events via `memory_write`.
