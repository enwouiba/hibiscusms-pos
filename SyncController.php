<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Services\SyncService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class SyncController extends Controller
{
    public function __construct(private SyncService $sync) {}

    public function push(Request $request): JsonResponse
    {
        $data = $request->validate([
            'device_id' => 'required|string|size:26',
            'store_id' => 'required|string|size:26',
            'operations' => 'required|array|max:500',
            'operations.*.op_id' => 'required|string|size:26',
            'operations.*.table' => 'required|string',
            'operations.*.op' => 'required|in:create,update,delete,upsert',
            'operations.*.row_id' => 'required|string|size:26',
            'operations.*.payload' => 'sometimes|array',
            'operations.*.version' => 'required|string',
            'operations.*.client_at' => 'required|date',
        ]);

        $user = $request->user();
        if (!$user->canAccessStore($data['store_id'])) {
            return response()->json(['message' => 'Pa gen aksè ak magazen sa.'], 403);
        }

        $results = $this->sync->push($user, $data['device_id'], $data['store_id'], $data['operations']);

        Device::where('id', $data['device_id'])->update([
            'last_seen_at' => now(),
        ]);

        return response()->json(['results' => $results]);
    }

    public function pull(Request $request): JsonResponse
    {
        $data = $request->validate([
            'store_id' => 'required|string|size:26',
            'since' => 'nullable|integer|min:0',
            'limit' => 'nullable|integer|min:1|max:1000',
            'device_id' => 'required|string|size:26',
        ]);

        $user = $request->user();
        if (!$user->canAccessStore($data['store_id'])) {
            return response()->json(['message' => 'Pa gen aksè ak magazen sa.'], 403);
        }

        $result = $this->sync->pull(
            $user,
            $data['store_id'],
            (int) ($data['since'] ?? 0),
            (int) ($data['limit'] ?? 500),
        );

        Device::where('id', $data['device_id'])->update([
            'last_seen_at' => now(),
            'last_sync_cursor' => $result['cursor'],
        ]);

        return response()->json($result);
    }

    /**
     * Bootstrap konplè pou yon aparèy ki fèk enstale.
     * Retounen tout done pou yon magazen.
     */
    public function bootstrap(Request $request): JsonResponse
    {
        $data = $request->validate([
            'store_id' => 'required|string|size:26',
        ]);
        $user = $request->user();
        if (!$user->canAccessStore($data['store_id'])) {
            return response()->json(['message' => 'Pa gen aksè ak magazen sa.'], 403);
        }
        $result = $this->sync->pull($user, $data['store_id'], 0, 5000);
        return response()->json($result);
    }
}
