module storage

import encoding.base64
import json
import net.http
import os

pub struct PollyLinkOfferEnvelope {
pub:
	offer    SyncOffer
	manifest SyncManifest
}

struct SyncOfferRequestDto {
	branch_name      string
	prediction_depth int
	target_branch    string
}

struct SyncNegotiateRequestDto {
	offer        SyncOfferDto
	manifest     SyncManifestDto
	use_manifest bool
}

struct SyncExchangeRequestDto {
	offer   SyncOfferDto
	missing SyncMissingSetDto
}

struct SyncFullExchangeRequestDto {
	offer SyncOfferDto
}

struct SyncApplyRequestDto {
	exchange SyncExchangeDto
}

struct SyncOfferEnvelopeDto {
	offer        SyncOfferDto
	manifest     SyncManifestDto
	has_manifest bool
}

struct SyncOfferDto {
	request_local_root_hash string
	request_branch_name     string
	expected_old_commit_cid string
	target_commit_cid       string
	target_root_cid         string
}

struct SyncManifestDto {
	offer            SyncOfferDto
	prediction_depth int
	level_1_hashes   []string
	predicted_hashes []string
}

struct SyncMissingSetDto {
	missing_commit_cids []string
	missing_node_cids   []string
}

struct SyncExchangeDto {
	session SyncSessionDto
	plan    SyncPlanDto
	packets []DataPacketDto
}

struct SyncSessionDto {
	request_local_root_hash string
	request_branch_name     string
	expected_old_commit_cid string
	target_commit_cid       string
}

struct SyncPlanDto {
	request_local_root_hash string
	request_branch_name     string
	target_commit_cid       string
	target_root_cid         string
	missing_commit_cids     []string
	missing_node_cids       []string
}

struct DataPacketDto {
	kind     string
	cid      string
	data_b64 string
}

struct BranchDto {
	name       string
	commit_cid string
}

struct ErrorDto {
	error string
}

fn sync_offer_to_dto(offer SyncOffer) SyncOfferDto {
	return SyncOfferDto{
		request_local_root_hash: offer.request.local_root_hash
		request_branch_name: offer.request.branch_name
		expected_old_commit_cid: offer.expected_old_commit_cid
		target_commit_cid: offer.target_commit_cid
		target_root_cid: offer.target_root_cid
	}
}

fn sync_offer_from_dto(dto SyncOfferDto) SyncOffer {
	return SyncOffer{
		request: SyncRequest{
			local_root_hash: dto.request_local_root_hash
			branch_name: dto.request_branch_name
		}
		expected_old_commit_cid: dto.expected_old_commit_cid
		target_commit_cid: dto.target_commit_cid
		target_root_cid: dto.target_root_cid
	}
}

fn sync_manifest_to_dto(manifest SyncManifest) SyncManifestDto {
	return SyncManifestDto{
		offer: sync_offer_to_dto(manifest.offer)
		prediction_depth: manifest.prediction_depth
		level_1_hashes: manifest.level_1_hashes.clone()
		predicted_hashes: manifest.predicted_hashes.clone()
	}
}

fn sync_manifest_from_dto(dto SyncManifestDto) SyncManifest {
	return SyncManifest{
		offer: sync_offer_from_dto(dto.offer)
		prediction_depth: dto.prediction_depth
		level_1_hashes: dto.level_1_hashes.clone()
		predicted_hashes: dto.predicted_hashes.clone()
	}
}

fn sync_missing_set_to_dto(missing SyncMissingSet) SyncMissingSetDto {
	return SyncMissingSetDto{
		missing_commit_cids: missing.missing_commit_cids.clone()
		missing_node_cids: missing.missing_node_cids.clone()
	}
}

fn sync_missing_set_from_dto(dto SyncMissingSetDto) SyncMissingSet {
	return SyncMissingSet{
		missing_commit_cids: dto.missing_commit_cids.clone()
		missing_node_cids: dto.missing_node_cids.clone()
	}
}

fn sync_session_to_dto(session SyncSession) SyncSessionDto {
	return SyncSessionDto{
		request_local_root_hash: session.request.local_root_hash
		request_branch_name: session.request.branch_name
		expected_old_commit_cid: session.expected_old_commit_cid
		target_commit_cid: session.target_commit_cid
	}
}

fn sync_session_from_dto(dto SyncSessionDto) SyncSession {
	return SyncSession{
		request: SyncRequest{
			local_root_hash: dto.request_local_root_hash
			branch_name: dto.request_branch_name
		}
		expected_old_commit_cid: dto.expected_old_commit_cid
		target_commit_cid: dto.target_commit_cid
	}
}

fn sync_plan_to_dto(plan SyncPlan) SyncPlanDto {
	return SyncPlanDto{
		request_local_root_hash: plan.request.local_root_hash
		request_branch_name: plan.request.branch_name
		target_commit_cid: plan.target_commit_cid
		target_root_cid: plan.target_root_cid
		missing_commit_cids: plan.missing_commit_cids.clone()
		missing_node_cids: plan.missing_node_cids.clone()
	}
}

fn sync_plan_from_dto(dto SyncPlanDto) SyncPlan {
	return SyncPlan{
		request: SyncRequest{
			local_root_hash: dto.request_local_root_hash
			branch_name: dto.request_branch_name
		}
		target_commit_cid: dto.target_commit_cid
		target_root_cid: dto.target_root_cid
		missing_commit_cids: dto.missing_commit_cids.clone()
		missing_node_cids: dto.missing_node_cids.clone()
	}
}

fn data_packet_to_dto(packet DataPacket) DataPacketDto {
	return DataPacketDto{
		kind: match packet.kind {
			.node { 'node' }
			.commit { 'commit' }
		}
		cid: packet.cid
		data_b64: base64.encode(packet.data)
	}
}

fn data_packet_from_dto(dto DataPacketDto) !DataPacket {
	return DataPacket{
		kind: match dto.kind {
			'node' { SyncObjectKind.node }
			'commit' { SyncObjectKind.commit }
			else { return error('invalid packet kind: ${dto.kind}') }
		}
		cid: dto.cid
		data: base64.decode(dto.data_b64)
	}
}

fn sync_exchange_to_dto(exchange SyncExchange) SyncExchangeDto {
	mut packets := []DataPacketDto{cap: exchange.packets.len}
	for packet in exchange.packets {
		packets << data_packet_to_dto(packet)
	}
	return SyncExchangeDto{
		session: sync_session_to_dto(exchange.session)
		plan: sync_plan_to_dto(exchange.plan)
		packets: packets
	}
}

fn sync_exchange_from_dto(dto SyncExchangeDto) !SyncExchange {
	mut packets := []DataPacket{cap: dto.packets.len}
	for packet in dto.packets {
		packets << data_packet_from_dto(packet)!
	}
	return SyncExchange{
		session: sync_session_from_dto(dto.session)
		plan: sync_plan_from_dto(dto.plan)
		packets: packets
	}
}

fn branch_to_dto(branch Branch) BranchDto {
	return BranchDto{
		name: branch.name
		commit_cid: branch.commit_cid
	}
}

fn branch_from_dto(dto BranchDto) Branch {
	return Branch{
		name: dto.name
		commit_cid: dto.commit_cid
	}
}

fn json_ok(body string) http.Response {
	mut resp := http.Response{
		body: body
	}
	resp.header = http.new_header(key: .content_type, value: 'application/json')
	resp.set_status(.ok)
	return resp
}

fn json_error(status http.Status, message string) http.Response {
	payload := json.encode(ErrorDto{
		error: message
	})
	mut resp := http.Response{
		body: payload
	}
	resp.header = http.new_header(key: .content_type, value: 'application/json')
	resp.set_status(status)
	return resp
}

fn sidecar_repo_meta_path(root_dir string) string {
	return os.join_path(root_dir, '.pollydb', 'repo.meta')
}

fn open_sidecar_repository(root_dir string, default_branch string) !PersistentRepository {
	return PersistentRepository.open_default(root_dir, default_branch)
}

pub struct PollyLinkSidecarHandler {
pub:
	root_dir        string
	default_branch  string
}

fn (handler PollyLinkSidecarHandler) serve_offer(req http.Request) http.Response {
	payload := json.decode(SyncOfferRequestDto, req.data) or {
		return json_error(.bad_request, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, handler.default_branch) or {
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	offer := sync_offer_for_branch(mut repo, payload.branch_name) or {
		return json_error(.bad_request, err.msg())
	}
	mut effective_offer := offer
	if payload.target_branch.len > 0 {
		effective_offer = SyncOffer{
			request: SyncRequest{
				local_root_hash: offer.request.local_root_hash
				branch_name: payload.target_branch
			}
			expected_old_commit_cid: offer.expected_old_commit_cid
			target_commit_cid: offer.target_commit_cid
			target_root_cid: offer.target_root_cid
		}
	}
	if payload.prediction_depth > 0 {
		manifest := effective_offer.manifest_with_depth(payload.prediction_depth, mut repo.node_store) or {
			return json_error(.internal_server_error, err.msg())
		}
		return json_ok(json.encode(SyncOfferEnvelopeDto{
			offer: sync_offer_to_dto(effective_offer)
			manifest: sync_manifest_to_dto(manifest)
			has_manifest: true
		}))
	}
	return json_ok(json.encode(SyncOfferEnvelopeDto{
		offer: sync_offer_to_dto(effective_offer)
		has_manifest: false
	}))
}

fn (handler PollyLinkSidecarHandler) serve_missing(req http.Request) http.Response {
	payload := json.decode(SyncNegotiateRequestDto, req.data) or {
		return json_error(.bad_request, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, handler.default_branch) or {
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	missing := if payload.use_manifest {
		sync_missing_for_manifest(mut repo, sync_manifest_from_dto(payload.manifest)) or {
			return json_error(.bad_request, err.msg())
		}
	} else {
		sync_missing_for_offer(mut repo, sync_offer_from_dto(payload.offer)) or {
			return json_error(.bad_request, err.msg())
		}
	}
	return json_ok(json.encode(sync_missing_set_to_dto(missing)))
}

fn (handler PollyLinkSidecarHandler) serve_exchange(req http.Request) http.Response {
	payload := json.decode(SyncExchangeRequestDto, req.data) or {
		return json_error(.bad_request, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, handler.default_branch) or {
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	exchange := sync_exchange_for_missing(mut repo, sync_offer_from_dto(payload.offer), sync_missing_set_from_dto(payload.missing)) or {
		return json_error(.bad_request, err.msg())
	}
	return json_ok(json.encode(sync_exchange_to_dto(exchange)))
}

fn (handler PollyLinkSidecarHandler) serve_exchange_full(req http.Request) http.Response {
	payload := json.decode(SyncFullExchangeRequestDto, req.data) or {
		return json_error(.bad_request, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, handler.default_branch) or {
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	exchange := full_sync_exchange_for_offer(mut repo, sync_offer_from_dto(payload.offer)) or {
		return json_error(.bad_request, err.msg())
	}
	return json_ok(json.encode(sync_exchange_to_dto(exchange)))
}

fn (handler PollyLinkSidecarHandler) serve_apply(req http.Request) http.Response {
	payload := json.decode(SyncApplyRequestDto, req.data) or {
		return json_error(.bad_request, err.msg())
	}
	exchange := sync_exchange_from_dto(payload.exchange) or {
		return json_error(.bad_request, err.msg())
	}
	mut repo := open_sidecar_repository(handler.root_dir, handler.default_branch) or {
		return json_error(.internal_server_error, err.msg())
	}
	defer {
		repo.close() or {}
	}
	branch := apply_exchange_to_repo(mut repo, exchange) or {
		return json_error(.bad_request, err.msg())
	}
	return json_ok(json.encode(branch_to_dto(branch)))
}

pub fn (handler PollyLinkSidecarHandler) handle(req http.Request) http.Response {
	path := req.url.all_before('?')
	if req.method == .get && path == '/health' {
		return json_ok('{"status":"ok"}')
	}
	if req.method == .post && path == '/v1/sync/offer' {
		return handler.serve_offer(req)
	}
	if req.method == .post && path == '/v1/sync/missing' {
		return handler.serve_missing(req)
	}
	if req.method == .post && path == '/v1/sync/exchange' {
		return handler.serve_exchange(req)
	}
	if req.method == .post && path == '/v1/sync/exchange-full' {
		return handler.serve_exchange_full(req)
	}
	if req.method == .post && path == '/v1/sync/apply' {
		return handler.serve_apply(req)
	}
	return json_error(.not_found, 'unknown route: ${path}')
}

pub fn start_pollylink_sidecar(root_dir string, default_branch string, addr string) !&http.Server {
	mut server := &http.Server{
		addr: addr
		handler: PollyLinkSidecarHandler{
			root_dir: root_dir
			default_branch: default_branch
		}
		show_startup_message: false
	}
	spawn server.listen_and_serve()
	server.wait_till_running()!
	return server
}

pub struct PollyLinkClient {
pub:
	base_url string
}

struct ApplyExchangeResult {
	ok        bool
	branch    Branch
	error_msg string
}

fn is_branch_head_changed_error(err_msg string) bool {
	return err_msg.contains('branch head changed during compare-and-swap')
}

fn (client PollyLinkClient) endpoint(path string) string {
	return client.base_url.trim_right('/') + path
}

fn (client PollyLinkClient) post_json(path string, body string) !http.Response {
	response := http.post_json(client.endpoint(path), body)!
	if response.status_code >= 400 {
		return error(response.body)
	}
	return response
}

fn (client PollyLinkClient) post_json_raw(path string, body string) !http.Response {
	return http.post_json(client.endpoint(path), body)!
}

pub fn (client PollyLinkClient) offer(branch_name string, target_branch string, prediction_depth int) !PollyLinkOfferEnvelope {
	response := client.post_json('/v1/sync/offer', json.encode(SyncOfferRequestDto{
		branch_name: branch_name
		target_branch: target_branch
		prediction_depth: prediction_depth
	}))!
	payload := json.decode(SyncOfferEnvelopeDto, response.body)!
	return PollyLinkOfferEnvelope{
		offer: sync_offer_from_dto(payload.offer)
		manifest: sync_manifest_from_dto(payload.manifest)
	}
}

pub fn (client PollyLinkClient) negotiate_missing(offer SyncOffer, manifest SyncManifest, use_manifest bool) !SyncMissingSet {
	response := client.post_json('/v1/sync/missing', json.encode(SyncNegotiateRequestDto{
		offer: sync_offer_to_dto(offer)
		manifest: sync_manifest_to_dto(manifest)
		use_manifest: use_manifest
	}))!
	payload := json.decode(SyncMissingSetDto, response.body)!
	return sync_missing_set_from_dto(payload)
}

pub fn (client PollyLinkClient) fetch_exchange(offer SyncOffer, missing SyncMissingSet) !SyncExchange {
	response := client.post_json('/v1/sync/exchange', json.encode(SyncExchangeRequestDto{
		offer: sync_offer_to_dto(offer)
		missing: sync_missing_set_to_dto(missing)
	}))!
	payload := json.decode(SyncExchangeDto, response.body)!
	return sync_exchange_from_dto(payload)
}

pub fn (client PollyLinkClient) fetch_full_exchange(offer SyncOffer) !SyncExchange {
	response := client.post_json('/v1/sync/exchange-full', json.encode(SyncFullExchangeRequestDto{
		offer: sync_offer_to_dto(offer)
	}))!
	payload := json.decode(SyncExchangeDto, response.body)!
	return sync_exchange_from_dto(payload)
}

pub fn (client PollyLinkClient) apply_exchange(exchange SyncExchange) !Branch {
	response := client.post_json('/v1/sync/apply', json.encode(SyncApplyRequestDto{
		exchange: sync_exchange_to_dto(exchange)
	}))!
	payload := json.decode(BranchDto, response.body)!
	return branch_from_dto(payload)
}

fn (client PollyLinkClient) try_apply_exchange(exchange SyncExchange) !ApplyExchangeResult {
	response := client.post_json_raw('/v1/sync/apply', json.encode(SyncApplyRequestDto{
		exchange: sync_exchange_to_dto(exchange)
	}))!
	if response.status_code >= 400 {
		payload := json.decode(ErrorDto, response.body) or {
			return ApplyExchangeResult{
				ok: false
				error_msg: response.body
			}
		}
		return ApplyExchangeResult{
			ok: false
			error_msg: payload.error
		}
	}
	payload := json.decode(BranchDto, response.body)!
	return ApplyExchangeResult{
		ok: true
		branch: branch_from_dto(payload)
	}
}

fn fetch_remote_branch_into_repo(mut repo PersistentRepository, client PollyLinkClient, branch_name string) !SyncOffer {
	envelope := client.offer(branch_name, branch_name, 0)!
	exchange := client.fetch_full_exchange(envelope.offer)!
	import_sync_exchange_objects(mut repo, exchange)!
	return envelope.offer
}

pub fn build_auto_merge_offer_for_remote_offer(mut source_repo PersistentRepository, source_branch string, target_branch string, remote_offer SyncOffer) !SyncOffer {
	source_branch_head := source_repo.branch(source_branch)!
	source_commit := source_repo.commit_store.get(source_branch_head.commit_cid)!
	base_commit := source_repo.repo.merge_base_commit(source_commit.cid, remote_offer.target_commit_cid, mut source_repo.commit_store)!
	merge_result := auto_merge_by_roots(base_commit.root_cid, source_commit.root_cid, remote_offer.target_root_cid, ChunkConfig.default(), mut source_repo.node_store)!
	if merge_result.conflicts.len > 0 {
		return error('auto-merge required manual resolution: ${merge_result.conflicts.len} conflicts')
	}
	merge_meta := CommitMeta{
		author: 'pollylink'
		message: 'auto-merge ${source_branch} into ${target_branch}'
		timestamp: 0
	}
	snapshot := Snapshot.new(merge_result.tree, [source_commit.cid, remote_offer.target_commit_cid], merge_meta)
	snapshot.persist(mut source_repo.node_store, mut source_repo.commit_store)!
	return SyncOffer{
		request: SyncRequest{
			local_root_hash: snapshot.commit.root_cid
			branch_name: target_branch
		}
		expected_old_commit_cid: remote_offer.target_commit_cid
		target_commit_cid: snapshot.commit.cid
		target_root_cid: snapshot.commit.root_cid
	}
}

fn build_auto_merge_sidecar_exchange(mut source_repo PersistentRepository, source_branch string, client PollyLinkClient, target_branch string) !SyncExchange {
	remote_offer := fetch_remote_branch_into_repo(mut source_repo, client, target_branch)!
	merged_offer := build_auto_merge_offer_for_remote_offer(mut source_repo, source_branch, target_branch, remote_offer)!
	return full_sync_exchange_for_offer(mut source_repo, merged_offer)
}

pub fn push_branch_to_sidecar(mut source_repo PersistentRepository, source_branch string, client PollyLinkClient, target_branch string, policy SyncNegotiationPolicy) !SyncPushResult {
	prediction_depth := match policy {
		.manifest_depth1, .auto { 1 }
		.manifest_depth2 { 2 }
		.regular { 0 }
	}
	envelope := client.offer(source_branch, target_branch, prediction_depth)!
	use_manifest := prediction_depth > 0
	missing := client.negotiate_missing(envelope.offer, envelope.manifest, use_manifest)!
	exchange := sync_exchange_for_missing(mut source_repo, envelope.offer, missing)!
	first_apply := client.try_apply_exchange(exchange)!
	if first_apply.ok {
		return SyncPushResult{
			session: exchange.session
			exchange: exchange
			branch: first_apply.branch
		}
	}
	err_msg := first_apply.error_msg
	if !is_branch_head_changed_error(err_msg) {
		return error(err_msg)
	}
	merged_exchange := build_auto_merge_sidecar_exchange(mut source_repo, source_branch, client, target_branch)!
	merged_branch := client.apply_exchange(merged_exchange)!
	return SyncPushResult{
		session: merged_exchange.session
		exchange: merged_exchange
		branch: merged_branch
		auto_merged: true
	}
}

pub fn pull_branch_from_sidecar(mut target_repo PersistentRepository, target_branch string, client PollyLinkClient, source_branch string, policy SyncNegotiationPolicy) !SyncPullResult {
	prediction_depth := match policy {
		.manifest_depth1, .auto { 1 }
		.manifest_depth2 { 2 }
		.regular { 0 }
	}
	envelope := client.offer(source_branch, target_branch, prediction_depth)!
	missing := if prediction_depth > 0 {
		sync_missing_for_manifest(mut target_repo, envelope.manifest)!
	} else {
		sync_missing_for_offer(mut target_repo, envelope.offer)!
	}
	exchange := client.fetch_exchange(envelope.offer, missing)!
	branch := apply_exchange_to_repo(mut target_repo, exchange)!
	return SyncPullResult{
		session: exchange.session
		exchange: exchange
		branch: branch
	}
}
