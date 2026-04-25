-- Reverte status dos 14 pedidos afetados pelo bug do fallback público
UPDATE public.pedidos
SET status_pedido = 'postado'
WHERE id IN (
  '9e55cb5a-4257-42c6-91a3-8cb14e9fd132',
  '6e754295-8568-4749-bc15-f6ef1f23582f',
  'cec580ee-6d3c-48ce-9c3d-b25248d7028a',
  '4e93e73d-ae6b-4740-9f26-0ed579d9e340',
  'da002d15-4a50-4a0c-8a2f-b254fe2fc25f',
  'ba31ce99-9b33-49e3-bf75-fb05bb55eb88',
  '2befd036-8812-43df-aa75-d56bdd216506',
  '10a55370-253c-4122-a584-ab106cbb6238',
  '0c83456e-b4aa-4153-8367-b5e8e343f2fd',
  '8273afe5-a049-4dfd-85da-672a0a804808',
  '0b3b761d-f5b8-4bc0-8fc3-971a3a7a0e14',
  '31f4a4b4-e48c-4f1d-addb-fecd58943a03',
  '0a4e84a8-91bb-46b4-867f-04ad4478ed3c',
  'c09bc10b-4196-4df6-8fc7-2c2d9d924e63'
) AND status_pedido = 'entregue';

-- Auditoria
INSERT INTO public.log_atividades (usuario, acao, tabela_afetada, registro_id, detalhe)
SELECT
  'Sistema (Correção bug sync)',
  'Reversão: entregue -> postado',
  'pedidos',
  id,
  'Pedido #' || order_number || ' revertido para postado. Motivo: falso positivo do fallback público (muambator/linkcorreios retornaram página de exemplo).'
FROM public.pedidos
WHERE id IN (
  '9e55cb5a-4257-42c6-91a3-8cb14e9fd132',
  '6e754295-8568-4749-bc15-f6ef1f23582f',
  'cec580ee-6d3c-48ce-9c3d-b25248d7028a',
  '4e93e73d-ae6b-4740-9f26-0ed579d9e340',
  'da002d15-4a50-4a0c-8a2f-b254fe2fc25f',
  'ba31ce99-9b33-49e3-bf75-fb05bb55eb88',
  '2befd036-8812-43df-aa75-d56bdd216506',
  '10a55370-253c-4122-a584-ab106cbb6238',
  '0c83456e-b4aa-4153-8367-b5e8e343f2fd',
  '8273afe5-a049-4dfd-85da-672a0a804808',
  '0b3b761d-f5b8-4bc0-8fc3-971a3a7a0e14',
  '31f4a4b4-e48c-4f1d-addb-fecd58943a03',
  '0a4e84a8-91bb-46b4-867f-04ad4478ed3c',
  'c09bc10b-4196-4df6-8fc7-2c2d9d924e63'
);